#include "EventStreamClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QTimer>
#include <QUuid>

namespace {

    // What the UI is interested in. Deliberately a fixed list rather than something pages register
    // into: a subscription is a server-side object, and re-registering it every time a page opens
    // would cost a round trip per navigation for no gain - the events are small, and a page that
    // does not care simply ignores them.
    const QStringList kEventTypes = {
            QStringLiteral("esm.object.created"),
            QStringLiteral("esm.object.updated"),
            QStringLiteral("esm.object.deleted"),
            // Buckets change without any object changing - created, renamed, deleted - and a
            // window showing a bucket that another window just renamed is exactly what a listing
            // on a timer looks like.
            QStringLiteral("esm.bucket.modified"),
            QStringLiteral("esm.bucket.deleted"),
            QStringLiteral("eqs.message.sent"),
            QStringLiteral("ekm.key.created"),
    };

    // How long the server holds a receive open when there is nothing to report. Below the
    // request's own timeout, so a quiet installation ends each wait with an empty answer rather
    // than with a transport error.
    constexpr int kWaitSeconds = 20;
    constexpr int kRequestTimeoutMs = 30000;

    // A claim this UI never acknowledges - because it was closed mid-event - becomes visible again
    // after this, for the next window to pick up.
    constexpr int kVisibilitySeconds = 60;

    constexpr int kMaxEvents = 50;
    constexpr int kRetryMs = 5000;

    // After this many empty waits (~3 minutes at kWaitSeconds), the subscription is registered
    // again. Registering is an upsert, so doing it when it was not needed costs one request.
    constexpr int kRenewAfterQuietWaits = 10;

    QVariantMap toPayload(const QJsonObject &object) {
        QVariantMap payload;
        for (auto it = object.begin(); it != object.end(); ++it) {
            payload.insert(it.key(), it.value().toVariant());
        }
        return payload;
    }

}// namespace

EventStreamClient::EventStreamClient(EuclidBaseClient *baseClient, QObject *parent)
    : QObject(parent), m_base(baseClient),
      m_subscriber(QStringLiteral("rui-") + QUuid::createUuid().toString(QUuid::WithoutBraces)) {}

void EventStreamClient::start() {
    if (m_listening || m_waiting) {
        return;
    }
    m_stopping = false;
    subscribe();
}

void EventStreamClient::stop() {
    if (!m_listening && !m_waiting) {
        return;
    }
    // Flagged before the call so the receive currently in flight does not start another one when
    // it comes back - there is no way to cancel it, and its answer is still worth delivering.
    m_stopping = true;
    setListening(false);

    m_base->post(QStringLiteral("ees"), QStringLiteral("unsubscribe-events"),
                 QJsonObject{{QStringLiteral("name"), m_subscriber}}, true,
                 [](const QJsonObject &) {},
                 [](const QString &) {});
}

void EventStreamClient::subscribe() {
    QJsonArray eventTypes;
    for (const auto &eventType: kEventTypes) {
        eventTypes.append(eventType);
    }

    // Durable, because a client that polls has nothing else to deliver to: live events only reach
    // a websocket session, and this has none. The subscription is removed on stop(), so "durable"
    // here means "kept between one wait and the next", not kept forever - and marking it ephemeral
    // means a gateway restart clears whatever a window that died without stopping left behind.
    const QJsonObject body{
            {QStringLiteral("name"), m_subscriber},
            {QStringLiteral("eventTypes"), eventTypes},
            {QStringLiteral("mode"), QStringLiteral("durable")},
            {QStringLiteral("ephemeral"), true},
    };

    m_base->post(QStringLiteral("ees"), QStringLiteral("subscribe-events"), body, true,
                 [this](const QJsonObject &) {
                     setListening(true);
                     waitForEvents();
                 },
                 [this](const QString &message) {
                     // An installation whose ees module is not running is not an error to report
                     // in the UI: every page still refreshes on its timer, which is exactly what
                     // it did before this existed.
                     qWarning("EventStreamClient: could not subscribe (%s), falling back to timed refresh",
                              qUtf8Printable(message));
                     setListening(false);
                 });
}

void EventStreamClient::waitForEvents() {
    if (m_stopping || m_waiting) {
        return;
    }
    m_waiting = true;

    const QJsonObject body{
            {QStringLiteral("name"), m_subscriber},
            {QStringLiteral("maxEvents"), kMaxEvents},
            {QStringLiteral("waitTime"), kWaitSeconds},
            {QStringLiteral("visibilityTimeout"), kVisibilitySeconds},
    };

    m_base->post(QStringLiteral("ees"), QStringLiteral("receive-events"), body, true,
                 [this](const QJsonObject &response) {
                     m_waiting = false;

                     QStringList handled;
                     const QJsonArray events = response.value(QStringLiteral("events")).toArray();
                     for (const auto &value: events) {
                         const QJsonObject event = value.toObject();
                         const QString eventId = event.value(QStringLiteral("eventId")).toString();
                         if (!eventId.isEmpty()) {
                             handled.append(eventId);
                         }
                         emit eventReceived(event.value(QStringLiteral("eventType")).toString(),
                                            toPayload(event.value(QStringLiteral("payload")).toObject()));
                     }

                     // Acknowledged as soon as they are emitted: a page refreshing is not work
                     // that can fail in a way redelivery would fix, and an event left claimed
                     // would come back to the next window as if it were new.
                     acknowledge(handled);

                     m_quietWaits = events.isEmpty() ? m_quietWaits + 1 : 0;
                     if (m_stopping) {
                         return;
                     }
                     if (m_quietWaits >= kRenewAfterQuietWaits) {
                         m_quietWaits = 0;
                         subscribe();
                         return;
                     }
                     waitForEvents();
                 },
                 [this](const QString &message) {
                     m_waiting = false;
                     if (m_stopping) {
                         return;
                     }
                     qWarning("EventStreamClient: receive failed (%s), retrying", qUtf8Printable(message));
                     retryLater();
                 },
                 kRequestTimeoutMs);
}

void EventStreamClient::acknowledge(const QStringList &eventIds) {
    if (eventIds.isEmpty()) {
        return;
    }

    QJsonArray ids;
    for (const auto &eventId: eventIds) {
        ids.append(eventId);
    }

    m_base->post(QStringLiteral("ees"), QStringLiteral("ack-events"),
                 QJsonObject{{QStringLiteral("name"), m_subscriber}, {QStringLiteral("eventIds"), ids}}, true,
                 [](const QJsonObject &) {},
                 [](const QString &message) {
                     // The events come back when their visibility runs out, so the cost is a
                     // duplicate refresh rather than anything lost.
                     qWarning("EventStreamClient: could not acknowledge events (%s)", qUtf8Printable(message));
                 });
}

void EventStreamClient::retryLater() {
    QTimer::singleShot(kRetryMs, this, [this] {
        if (m_stopping) {
            return;
        }
        // Re-subscribing rather than only waiting again: the most likely reason a receive failed
        // is that the gateway went away, and its subscription may not have survived that.
        if (m_listening) {
            waitForEvents();
        } else {
            subscribe();
        }
    });
}

void EventStreamClient::setListening(const bool listening) {
    if (m_listening == listening) {
        return;
    }
    m_listening = listening;
    emit listeningChanged();
}
