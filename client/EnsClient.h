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

    // Messages
    Q_INVOKABLE void fetchMessages(const QString &topicErn, int pageIndex = 0, int pageSize = 100,
                                   const QString &sortColumn = QStringLiteral("created"),
                                   const QString &sortDirection = QStringLiteral("desc"));
    Q_INVOKABLE void publishMessage(const QString &topicErn, const QString &body, const QVariantMap &attributes);

signals:
    // Topics
    void topicsLoaded(const QVariantList &topics, int total);
    void topicsFailed(const QString &message);
    void topicsReload();
    void topicCreated(const QString &name);
    void topicCreateFailed(const QString &message);

    // Messages
    void messagesLoaded(const QString &topicErn, const QVariantList &messages, int total);
    void messagesFailed(const QString &topicErn, const QString &message);
    void messagesReload(const QString &topicErn);
    void messagePublished(const QString &topicErn);
    void messagePublishFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
