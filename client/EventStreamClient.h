#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class EuclidBaseClient;

// Tells the UI what happened, instead of the UI asking every few seconds.
//
// Every page in this application refreshes on a timer, which is both too slow (a file that lands
// in a bucket shows up whenever the timer next fires) and too busy (a page nobody is changing is
// re-fetched forever). This subscribes to euclid's event service once and emits eventReceived()
// as things actually happen, so a page can refresh when its own data changed and otherwise leave
// the server alone.
//
// It long-polls rather than holding a websocket: EES delivers to a connected websocket session or
// to a client that asks, and Qt WebSockets is not part of the static Qt this application links
// against - so it asks, with the server holding each request open until something arrives. The
// latency is the same in practice; what it costs is a durable subscription, which is why the
// subscription is removed again on stop().
class EventStreamClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool listening READ listening NOTIFY listeningChanged)

public:
    explicit EventStreamClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    [[nodiscard]]
    bool listening() const { return m_listening; }

    // Registers the subscription and starts waiting for events. Safe to call again while already
    // listening - it does nothing rather than opening a second waiter.
    Q_INVOKABLE void start();

    // Removes the subscription, along with anything still stored for it: the events are only
    // interesting to a window that is open, and a subscription left behind would accumulate them
    // for a UI that is not running.
    Q_INVOKABLE void stop();

    // Whether these events are wanted at all, from AppSettings::liveListUpdates().
    //
    // Every page that listens discards what arrives unless that setting is on, and it is off by
    // default - so subscribing regardless meant the server stored, and this claimed and
    // acknowledged, a stream of events thrown away at the first line of every handler. On one
    // installation that came to half a million stored events for a single window: an expensive way
    // to deliver nothing.
    //
    // Kept separate from start()/stop(), which say whether there is a session. The subscription
    // exists only while both are true, so it follows the setting being toggled mid-session as well
    // as signing in and out.
    void setEnabled(bool enabled);

signals:
    void listeningChanged();

    // One event, as published. eventType is e.g. "esm.object.created"; payload is the event's own
    // fields - bucketName, key, queueName, and so on - so a page can decide whether it is about
    // anything it is showing.
    void eventReceived(const QString &eventType, const QVariantMap &payload);

private:
    // Drops the subscription and stops waiting, without saying why - shared by stop() (the session
    // ended) and setEnabled(false) (the events are no longer wanted).
    void stopListening();

    void subscribe();
    void waitForEvents();
    void acknowledge(const QStringList &eventIds);
    void setListening(bool listening);
    void retryLater();

    EuclidBaseClient *m_base;
    // The subscriber name this UI claims events under. Unique per run: two windows watching the
    // same installation must both see everything, and sharing a name would have them take events
    // from each other.
    QString m_subscriber;
    bool m_listening{false};
    bool m_stopping{false};
    // Whether a signed-in session wants events - start() sets it, stop() clears it. Held apart
    // from m_enabled so that turning the setting off and on again during one session resubscribes
    // rather than waiting for the next sign-in.
    bool m_wanted{false};
    // AppSettings::liveListUpdates(), which defaults to off.
    bool m_enabled{false};
    // Set while a receive is in flight, so start() and the retry timer cannot stack up waiters.
    bool m_waiting{false};
    // Consecutive waits that came back with nothing. The subscription is renewed after enough of
    // them: a gateway restart clears subscriptions belonging to a client rather than a module, and
    // a cleared one is indistinguishable from a quiet installation - both answer with no events.
    int m_quietWaits{0};
};
