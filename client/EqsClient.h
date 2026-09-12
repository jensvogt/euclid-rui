#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// EQS (queue service) calls: queues and their messages.
class EqsClient : public QObject {
    Q_OBJECT

public:
    explicit EqsClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // Queues
    // "includeInternal" asks for euclid's own queues as well - the bucket queue behind a listener
    // and the like. The server honours it for administrators only and silently ignores it for
    // everyone else, so asking is never an error, it just changes nothing.
    Q_INVOKABLE void fetchQueues(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                 const QString &sortColumn = QStringLiteral("available"),
                                 const QString &sortDirection = QStringLiteral("desc"),
                                 bool includeInternal = false);
    // The settings default to what "create-queue" itself defaults to, so a caller that only has a
    // name can pass one. A queue created as another queue's dead letter queue is an ordinary queue
    // and usually wants that queue's settings, which is why they are all passable.
    //
    // Naming `dlqName` creates a second queue by that name and points the new queue at it, so that
    // messages received more than `maxRetries` times are moved into it. This is the only moment EQS
    // lets a dead letter queue be attached: there is no action that gives an existing queue one, so
    // a queue created without a DLQ here cannot be given one later. Both queues are created with
    // the same visibility, retry, length and delay settings - the server applies this one request
    // to each of them.
    Q_INVOKABLE void createQueue(const QString &name, const QString &dlqName = QString(),
                                 int visibility = 30, int maxRetries = 3,
                                 int maxMessageLength = 1048576, int delay = 0);
    Q_INVOKABLE void purgeQueue(const QString &queueErn);
    Q_INVOKABLE void deleteQueue(const QString &queueErn);

    // Takes a queue out of service and puts it back. What "stopped" means is narrower than it
    // sounds and is worth being exact about: "receive-messages" is refused with a 409, and nothing
    // else is. Sends still land, so a stopped queue goes on filling up; messages already in flight
    // are left alone, because a consumer that took one before the stop is still entitled to finish
    // with it. Nothing is lost either way - the queue keeps everything it holds.
    Q_INVOKABLE void stopQueue(const QString &queueErn);
    Q_INVOKABLE void startQueue(const QString &queueErn);

    // The three settings a queue carries that can be changed after it exists. All three govern
    // what happens to messages sent or received from here on, and none of them reaches back:
    //
    // - visibility: how long a received message stays invisible, 0 to 43200 seconds. A message
    //   already in flight keeps the window it was given, so shortening this cannot expire a lease
    //   under a consumer that is still working.
    // - delay: how long a sent message is held back before it can be received, 0 to 900 seconds.
    //   A message already waiting had its delay turned into a timestamp when it arrived.
    // - maxMessageLength: the largest message the queue accepts, in bytes. Zero is not "accept
    //   nothing" - it is the queue carrying no limit of its own, and sends are then measured
    //   against the installation's default of 1 MiB.
    Q_INVOKABLE void setQueueVisibility(const QString &queueErn, qint64 visibility);
    Q_INVOKABLE void setQueueDelay(const QString &queueErn, qint64 delay);
    Q_INVOKABLE void setQueueMaxMessageLength(const QString &queueErn, qint64 maxMessageLength);

    // Moves everything in a dead letter queue back to the queue it came from. Nothing on a queue
    // records that it *is* a dead letter queue - the relationship is only ever written by the
    // queues naming it - so the server answers "not a dead letter queue" for an ordinary one.
    //
    // `targetErn` names one of the queues that feed it, for the case where several do and the
    // messages that have no recorded origin have to be dealt with deliberately. Empty means: one
    // source, everything goes there; or several, and each message goes back where it came from.
    Q_INVOKABLE void redriveDlq(const QString &queueErn, const QString &targetErn = QString());

    // The ERNs every queue names as its dead letter queue, which is the only way to know that a
    // queue is one. Asked for separately from the table's own page: a dead letter queue and the
    // queue feeding it are rarely on the same page of ten.
    Q_INVOKABLE void fetchDeadLetterTargets();
    // Upserts the tag unconditionally (unlike set-queue-tag, this doesn't require the key to
    // already exist), matching an "Add" button's semantics.
    Q_INVOKABLE void addQueueTag(const QString &queueErn, const QString &key, const QString &value);
    // No-ops server-side if the queue doesn't have this tag key.
    Q_INVOKABLE void deleteQueueTag(const QString &queueErn, const QString &key);

    // Messages
    // Paged and sorted by the server, like every other list here: the page the table is showing is
    // the page that is asked for, rather than a fixed block that the window then slices.
    Q_INVOKABLE void fetchMessages(const QString &queueErn, int pageIndex = 0, int pageSize = 100,
                                   const QString &sortColumn = QStringLiteral("created"),
                                   const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void sendMessage(const QString &queueErn, const QString &body, const QString &priority, const QVariantMap &attributes);
    Q_INVOKABLE void deleteSqsMessage(const QString &queueErn, const QString &messageId);

signals:
    // Queues
    void queuesLoaded(const QVariantList &queues, int total);
    // The ERNs that are somebody's dead letter queue. Its own signal rather than queuesLoaded, so
    // the listing behind the table is not replaced by the one this asks for.
    void deadLetterTargetsLoaded(const QStringList &erns);
    // What the redrive moved: `targets` is [{queueErn, messages}], and `note` is set when messages
    // stayed behind because no source queue is recorded for them.
    void dlqRedriven(const QString &queueErn, int messages, int remaining, const QVariantList &targets, const QString &note);
    void dlqRedriveFailed(const QString &message);
    void queuesFailed(const QString &message);
    void queuesReload();
    // "AVAILABLE" or "STOPPED", as the server recorded it - not as the caller asked for it.
    void queueStatusChanged(const QString &queueErn, const QString &status);
    void queueStatusFailed(const QString &message);
    // The values the server recorded, read back from its answer rather than echoed from the ask.
    void queueVisibilityChanged(const QString &queueErn, qint64 visibility);
    void queueDelayChanged(const QString &queueErn, qint64 delay);
    // "effective" is what a send is measured against, which is the installation's default when the
    // queue carries no limit of its own.
    void queueMaxMessageLengthChanged(const QString &queueErn, qint64 maxMessageLength, qint64 effective);
    // Shared by the three: they are set from one dialog, which has one place to put an error.
    void queueConfigurationFailed(const QString &message);
    void queueCreated(const QString &name);
    void queueCreateFailed(const QString &message);
    void queueTagAdded(const QString &queueErn, const QString &key, const QString &value);
    void queueTagAddFailed(const QString &message);
    void queueTagDeleted(const QString &queueErn, const QString &key);
    void queueTagDeleteFailed(const QString &message);

    // Messages
    void messagesLoaded(const QString &queueErn, const QVariantList &messages, int total);
    void messagesFailed(const QString &queueErn, const QString &message);
    void messagesReload(const QString &queueErn);
    void messageSent(const QString &queueErn);
    void messageSendFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
