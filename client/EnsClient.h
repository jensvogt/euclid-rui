#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// ENS (notification service) calls: topics and the messages published to them.
class EnsClient : public QObject {
    Q_OBJECT

public:
    explicit EnsClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // Topics
    Q_INVOKABLE void fetchTopics(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                 const QString &sortColumn = QStringLiteral("name"),
                                 const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void createTopic(const QString &name, int maxMessageLength = 1048576);
    Q_INVOKABLE void purgeTopic(const QString &topicErn);
    Q_INVOKABLE void deleteTopic(const QString &topicErn);

    // Stops and resumes delivery. Not the same trade EQS's stop-queue makes, and worth being exact
    // about: a stopped topic still accepts publishes, but each message is kept as "HELD" instead of
    // being fanned out to the subscriptions. Starting it delivers the whole backlog, oldest first,
    // and answers with how many went - so a start is a burst of traffic through every subscription,
    // not a switch being flipped back.
    Q_INVOKABLE void stopTopic(const QString &topicErn);
    Q_INVOKABLE void startTopic(const QString &topicErn);

    // How long a message published to this topic is kept, in seconds. Two of the values are not
    // durations: 0 gives the topic no period of its own, so it follows
    // euclid.modules.ens.retention-period as that changes, and -1 keeps everything forever by
    // storing messages with no expiry at all. Anything below -1 is refused.
    //
    // Applies to what is published afterwards and to what is already stored: retention is a stamp
    // on each message, so shortening it does not reach back and re-stamp what is already there.
    Q_INVOKABLE void setTopicRetention(const QString &topicErn, qint64 retentionPeriod);

    // The largest message the topic accepts, in bytes. Has to be positive - zero would be a topic
    // that takes nothing, which is what stopping it says, reversibly. Applies to what is published
    // from here on; a message already in the topic was accepted under the rule in force when it
    // arrived and is not re-checked.
    Q_INVOKABLE void setTopicMaxMessageLength(const QString &topicErn, qint64 maxMessageLength);
    // Upserts the tag unconditionally (unlike set-topic-tag, this doesn't require the key to
    // already exist), matching an "Add" button's semantics.
    Q_INVOKABLE void addTopicTag(const QString &topicErn, const QString &key, const QString &value);
    // No-ops server-side if the topic doesn't have this tag key.
    Q_INVOKABLE void deleteTopicTag(const QString &topicErn, const QString &key);

    // Messages
    Q_INVOKABLE void fetchMessages(const QString &topicErn, int pageIndex = 0, int pageSize = 100,
                                   const QString &sortColumn = QStringLiteral("created"),
                                   const QString &sortDirection = QStringLiteral("desc"));
    Q_INVOKABLE void publishMessage(const QString &topicErn, const QString &body, const QVariantMap &attributes);

    // Subscriptions
    Q_INVOKABLE void fetchSubscriptions(const QString &topicErn);
    // type is the delivery protocol - only "SQS" is currently supported server-side.
    Q_INVOKABLE void subscribe(const QString &topicErn, const QString &type, const QString &targetErn);

signals:
    // Topics
    void topicsLoaded(const QVariantList &topics, int total);
    void topicsFailed(const QString &message);
    void topicsReload();
    void topicCreated(const QString &name);
    void topicCreateFailed(const QString &message);
    // The state the server recorded - "RUNNING" or "STOPPED", the same words the listing uses - and,
    // for a start, how many held messages it delivered on the way. Always 0 for a stop, which
    // releases nothing.
    void topicDeliveryChanged(const QString &topicErn, const QString &status, int released);
    void topicDeliveryFailed(const QString &message);
    // The values the server recorded, read back from its answer rather than echoed from the ask.
    void topicRetentionChanged(const QString &topicErn, qint64 retentionPeriod);
    void topicMaxMessageLengthChanged(const QString &topicErn, qint64 maxMessageLength);
    // Shared by both: they are set from one dialog, and it has one place to put an error.
    void topicConfigurationFailed(const QString &message);
    void topicTagAdded(const QString &topicErn, const QString &key, const QString &value);
    void topicTagAddFailed(const QString &message);
    void topicTagDeleted(const QString &topicErn, const QString &key);
    void topicTagDeleteFailed(const QString &message);

    // Messages
    void messagesLoaded(const QString &topicErn, const QVariantList &messages, int total);
    void messagesFailed(const QString &topicErn, const QString &message);
    void messagesReload(const QString &topicErn);
    void messagePublished(const QString &topicErn);
    void messagePublishFailed(const QString &message);

    // Subscriptions
    void subscriptionsLoaded(const QString &topicErn, const QVariantList &subscriptions, int total);
    void subscriptionsFailed(const QString &topicErn, const QString &message);
    void subscriptionCreated(const QString &topicErn);
    void subscriptionCreateFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
