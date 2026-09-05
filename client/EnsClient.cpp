#include "EnsClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonObject>

EnsClient::EnsClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EnsClient::fetchTopics(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ens", "list-topics", body, true,
         [this](const QJsonObject &response) {
             QVariantList topics;
             for (const QJsonArray array = response.value("topics").toArray(); const auto &value : array) {
                 const QJsonObject topic = value.toObject();
                 QVariantMap entry;
                 entry["name"] = topic.value("name").toString();
                 entry["ern"] = topic.value("ern").toString();
                 entry["owner"] = topic.value("owner").toString();
                 // 64-bit like the EQS and ESM totals: toInt() answers 0 rather than a truncated
                 // number once a byte count or a message count passes 2^31.
                 entry["size"] = topic.value("size").toInteger();
                 entry["messages"] = topic.value("messages").toInteger();
                 entry["maxMessageLength"] = topic.value("maxMessageLength").toInt();
                 entry["tags"] = topic.value("tags").toObject().toVariantMap();
                 entry["created"] = topic.value("created").toString();
                 entry["modified"] = topic.value("modified").toString();
                 topics << entry;
             }
             emit topicsLoaded(topics, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit topicsFailed(message);
         });
}

void EnsClient::createTopic(const QString &name, const int maxMessageLength) {
    QJsonObject body;
    body["name"] = name;
    body["maxMessageLength"] = maxMessageLength;

    m_base->post("ens", "create-topic", body, true,
         [this, name](const QJsonObject &response) {
             emit topicCreated(name);
             emit topicsReload();
         },
         [this](const QString &message) {
             emit topicCreateFailed(message);
         });
}

void EnsClient::purgeTopic(const QString &topicErn) {
    QJsonObject body;
    body["ern"] = topicErn;

    m_base->post("ens", "purge-topic", body, true,
         [this, topicErn](const QJsonObject &response) {
             emit messagesReload(topicErn);
             emit topicsReload();
         },
         [this](const QString &message) {
             emit topicsFailed(message);
         });
}

void EnsClient::deleteTopic(const QString &topicErn) {
    QJsonObject body;
    body["ern"] = topicErn;

    m_base->post("ens", "delete-topic", body, true,
         [this](const QJsonObject &response) {
             emit topicsReload();
         },
         [this](const QString &message) {
             emit topicsFailed(message);
         });
}

void EnsClient::addTopicTag(const QString &topicErn, const QString &key, const QString &value) {
    QJsonObject body;
    body["ern"] = topicErn;
    body["key"] = key;
    body["value"] = value;

    m_base->post("ens", "add-topic-tag", body, true,
         [this, topicErn, key, value](const QJsonObject &response) {
             emit topicTagAdded(topicErn, key, value);
             emit topicsReload();
         },
         [this](const QString &message) {
             emit topicTagAddFailed(message);
         });
}

void EnsClient::deleteTopicTag(const QString &topicErn, const QString &key) {
    QJsonObject body;
    body["ern"] = topicErn;
    body["key"] = key;

    m_base->post("ens", "delete-topic-tag", body, true,
         [this, topicErn, key](const QJsonObject &response) {
             emit topicTagDeleted(topicErn, key);
             emit topicsReload();
         },
         [this](const QString &message) {
             emit topicTagDeleteFailed(message);
         });
}

void EnsClient::fetchMessages(const QString &topicErn, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["topicErn"] = topicErn;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ens", "list-messages", body, true,
         [this, topicErn](const QJsonObject &response) {
             QVariantList messages;
             for (const QJsonArray array = response.value("messages").toArray(); const auto &value : array) {
                 const QJsonObject message = value.toObject();
                 QVariantMap entry;
                 entry["messageId"] = message.value("messageId").toString();
                 entry["ern"] = message.value("ern").toString();
                 entry["topicErn"] = message.value("topicErn").toString();
                 entry["status"] = message.value("status").toString();
                 entry["body"] = message.value("body").toString();
                 entry["md5Body"] = message.value("md5Body").toString();
                 entry["md5Attributes"] = message.value("md5Attributes").toString();
                 entry["contentType"] = message.value("contentType").toString();
                 entry["created"] = message.value("created").toString();
                 entry["modified"] = message.value("modified").toString();
                 messages << entry;
             }
             emit messagesLoaded(topicErn, messages, response.value("total").toInt());
         },
         [this, topicErn](const QString &message) {
             emit messagesFailed(topicErn, message);
         });
}

void EnsClient::publishMessage(const QString &topicErn, const QString &body, const QVariantMap &attributes) {
    QJsonObject attrs;
    for (auto it = attributes.constBegin(); it != attributes.constEnd(); ++it) {
        QJsonObject typed;
        typed["type"] = "string";
        typed["value"] = it.value().toString();
        attrs[it.key()] = typed;
    }

    QJsonObject requestBody;
    // The wire field is "ern", not "topicErn", despite the C++ member name on the server's
    // PublishMessageRequest DTO - same quirk as EQS's send-message.
    requestBody["ern"] = topicErn;
    requestBody["body"] = body;
    requestBody["attributes"] = attrs;

    m_base->post("ens", "publish-message", requestBody, true,
         [this, topicErn](const QJsonObject &response) {
             emit messagePublished(topicErn);
             emit messagesReload(topicErn);
         },
         [this](const QString &message) {
             emit messagePublishFailed(message);
         });
}

void EnsClient::fetchSubscriptions(const QString &topicErn) {
    QJsonObject body;
    body["topicErn"] = topicErn;

    m_base->post("ens", "list-subscriptions", body, true,
         [this, topicErn](const QJsonObject &response) {
             QVariantList subscriptions;
             for (const QJsonArray array = response.value("subscriptions").toArray(); const auto &value : array) {
                 const QJsonObject subscription = value.toObject();
                 QVariantMap entry;
                 entry["ern"] = subscription.value("ern").toString();
                 entry["sourceErn"] = subscription.value("sourceErn").toString();
                 entry["type"] = subscription.value("type").toString();
                 entry["targetErn"] = subscription.value("targetErn").toString();
                 entry["created"] = subscription.value("created").toString();
                 entry["modified"] = subscription.value("modified").toString();
                 subscriptions << entry;
             }
             emit subscriptionsLoaded(topicErn, subscriptions, response.value("total").toInt());
         },
         [this, topicErn](const QString &message) {
             emit subscriptionsFailed(topicErn, message);
         });
}

void EnsClient::subscribe(const QString &topicErn, const QString &type, const QString &targetErn) {
    QJsonObject body;
    body["sourceErn"] = topicErn;
    body["type"] = type;
    body["targetErn"] = targetErn;

    m_base->post("ens", "subscribe", body, true,
         [this, topicErn](const QJsonObject &response) {
             emit subscriptionCreated(topicErn);
         },
         [this](const QString &message) {
             emit subscriptionCreateFailed(message);
         });
}
