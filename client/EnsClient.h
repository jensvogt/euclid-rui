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
