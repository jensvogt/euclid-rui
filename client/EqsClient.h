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
    Q_INVOKABLE void fetchQueues(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                 const QString &sortColumn = QStringLiteral("available"),
                                 const QString &sortDirection = QStringLiteral("desc"));
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
    // Upserts the tag unconditionally (unlike set-queue-tag, this doesn't require the key to
    // already exist), matching an "Add" button's semantics.
    Q_INVOKABLE void addQueueTag(const QString &queueErn, const QString &key, const QString &value);
    // No-ops server-side if the queue doesn't have this tag key.
    Q_INVOKABLE void deleteQueueTag(const QString &queueErn, const QString &key);

    // Messages
    Q_INVOKABLE void fetchMessages(const QString &queueErn, int pageIndex = 0, int pageSize = 100);
    Q_INVOKABLE void sendMessage(const QString &queueErn, const QString &body, const QString &priority, const QVariantMap &attributes);
    Q_INVOKABLE void deleteSqsMessage(const QString &queueErn, const QString &messageId);

signals:
    // Queues
    void queuesLoaded(const QVariantList &queues, int total);
    void queuesFailed(const QString &message);
    void queuesReload();
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
