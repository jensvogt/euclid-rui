#include "EqsClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonObject>

EqsClient::EqsClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EqsClient::fetchQueues(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("eqs", "list-queues", body, true,
         [this](const QJsonObject &response) {
             QVariantList queues;
             for (const QJsonArray array = response.value("queues").toArray(); const auto &value : array) {
                 const QJsonObject queue = value.toObject();
                 QVariantMap entry;
                 entry["name"] = queue.value("name").toString();
                 entry["ern"] = queue.value("ern").toString();
                 entry["owner"] = queue.value("owner").toString();
                 // Read as 64-bit for the reason ESM's bucket size is: past 2^31 toInt() returns
                 // its default instead of the number, which shows an overflowing queue as empty.
                 // The configured limits below stay int - they are settings, not totals.
                 entry["available"] = queue.value("available").toInteger();
                 entry["delayed"] = queue.value("delayed").toInteger();
                 entry["invisible"] = queue.value("invisible").toInteger();
                 entry["size"] = queue.value("size").toInteger();
                 entry["delay"] = queue.value("delay").toInt();
                 entry["visibility"] = queue.value("visibility").toInt();
                 entry["maxMessageLength"] = queue.value("maxMessageLength").toInt();
                 entry["maxReceiveCount"] = queue.value("maxReceiveCount").toInt();
                 entry["deadLetterQueueArn"] = queue.value("deadLetterQueueArn").toString();
                 entry["tags"] = queue.value("tags").toObject().toVariantMap();
                 entry["created"] = queue.value("created").toString();
                 entry["modified"] = queue.value("modified").toString();
                 queues << entry;
             }
             emit queuesLoaded(queues, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit queuesFailed(message);
         });
}

void EqsClient::createQueue(const QString &name, const QString &dlqName, const int visibility,
                            const int maxRetries, const int maxMessageLength, const int delay) {
    QJsonObject body;
    body["name"] = name;
    body["visibility"] = visibility;
    body["maxRetries"] = maxRetries;
    body["maxMessageLength"] = maxMessageLength;
    body["dlqName"] = dlqName;
    body["delay"] = delay;

    m_base->post("eqs", "create-queue", body, true,
         [this, name](const QJsonObject &response) {
             emit queueCreated(name);
             emit queuesReload();
         },
         [this](const QString &message) {
             emit queueCreateFailed(message);
         });
}

void EqsClient::purgeQueue(const QString &queueErn) {
    QJsonObject body;
    body["ern"] = queueErn;

    m_base->post("eqs", "purge-queue", body, true,
         [this, queueErn](const QJsonObject &response) {
             emit messagesReload(queueErn);
             emit queuesReload();
         },
         [this](const QString &message) {
             emit queuesFailed(message);
         });
}

void EqsClient::deleteQueue(const QString &queueErn) {
    QJsonObject body;
    body["ern"] = queueErn;

    m_base->post("eqs", "delete-queue", body, true,
         [this](const QJsonObject &response) {
             emit queuesReload();
         },
         [this](const QString &message) {
             emit queuesFailed(message);
         });
}

void EqsClient::addQueueTag(const QString &queueErn, const QString &key, const QString &value) {
    QJsonObject body;
    body["ern"] = queueErn;
    body["key"] = key;
    body["value"] = value;

    m_base->post("eqs", "add-queue-tag", body, true,
         [this, queueErn, key, value](const QJsonObject &response) {
             emit queueTagAdded(queueErn, key, value);
             emit queuesReload();
         },
         [this](const QString &message) {
             emit queueTagAddFailed(message);
         });
}

void EqsClient::deleteQueueTag(const QString &queueErn, const QString &key) {
    QJsonObject body;
    body["ern"] = queueErn;
    body["key"] = key;

    m_base->post("eqs", "delete-queue-tag", body, true,
         [this, queueErn, key](const QJsonObject &response) {
             emit queueTagDeleted(queueErn, key);
             emit queuesReload();
         },
         [this](const QString &message) {
             emit queueTagDeleteFailed(message);
         });
}

void EqsClient::fetchMessages(const QString &queueErn, const int pageIndex, const int pageSize) {
    QJsonObject body;
    body["queueErn"] = queueErn;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = "created";
    body["sortDirection"] = "asc";

    m_base->post("eqs", "list-messages", body, true,
         [this, queueErn](const QJsonObject &response) {
             QVariantList messages;
             for (const QJsonArray array = response.value("messages").toArray(); const auto &value : array) {
                 const QJsonObject message = value.toObject();
                 QVariantMap entry;
                 entry["messageId"] = message.value("messageId").toString();
                 entry["ern"] = message.value("ern").toString();
                 entry["queueErn"] = message.value("queueErn").toString();
                 entry["status"] = message.value("status").toString();
                 entry["priority"] = message.value("priority").toString();
                 entry["body"] = message.value("body").toString();
                 entry["receiptHandle"] = message.value("receiptHandle").toString();
                 entry["md5Body"] = message.value("md5Body").toString();
                 entry["md5Attributes"] = message.value("md5Attributes").toString();
                 entry["size"] = message.value("size").toInteger();
                 entry["contentType"] = message.value("contentType").toString();
                 entry["created"] = message.value("created").toString();
                 entry["modified"] = message.value("modified").toString();
                 messages << entry;
             }
             emit messagesLoaded(queueErn, messages, response.value("total").toInt());
         },
         [this, queueErn](const QString &message) {
             emit messagesFailed(queueErn, message);
         });
}

void EqsClient::sendMessage(const QString &queueErn, const QString &body, const QString &priority, const QVariantMap &attributes) {
    QJsonObject attrs;
    for (auto it = attributes.constBegin(); it != attributes.constEnd(); ++it) {
        QJsonObject typed;
        typed["type"] = "string";
        typed["value"] = it.value().toString();
        attrs[it.key()] = typed;
    }

    QJsonObject requestBody;
    requestBody["ern"] = queueErn;
    requestBody["body"] = body;
    requestBody["attributes"] = attrs;
    requestBody["priority"] = priority;

    m_base->post("eqs", "send-message", requestBody, true,
         [this, queueErn](const QJsonObject &response) {
             emit messageSent(queueErn);
             emit messagesReload(queueErn);
         },
         [this](const QString &message) {
             emit messageSendFailed(message);
         });
}

void EqsClient::deleteSqsMessage(const QString &queueErn, const QString &messageId) {
    QJsonObject body;
    body["messageId"] = messageId;

    m_base->post("eqs", "delete-message", body, true,
         [this, queueErn](const QJsonObject &response) {
             emit messagesReload(queueErn);
         },
         [this](const QString &message) {
             emit queuesFailed(message);
         });
}
