#include "EtsClient.h"
#include "EuclidBaseClient.h"

namespace {
// Turns one "list-servers"/"get-server" entry into the map the QML pages read.
QVariantMap serverToMap(const QJsonObject &server) {
    QVariantMap entry;
    entry["serverId"] = server.value("serverId").toString();
    entry["ern"] = server.value("ern").toString();
    entry["accountId"] = server.value("accountId").toString();
    entry["region"] = server.value("region").toString();
    entry["protocol"] = server.value("protocol").toString();
    entry["address"] = server.value("address").toString();
    entry["port"] = server.value("port").toInt();
    entry["bucketName"] = server.value("bucketName").toString();
    entry["bucketErn"] = server.value("bucketErn").toString();
    entry["userIds"] = server.value("userIds").toArray().toVariantList();
    entry["userGroups"] = server.value("userGroups").toArray().toVariantList();
    entry["state"] = server.value("state").toString();
    entry["desiredState"] = server.value("desiredState").toString();
    entry["hostKey"] = server.value("hostKey").toString();
    entry["pasvMin"] = server.value("pasvMin").toInt();
    entry["pasvMax"] = server.value("pasvMax").toInt();
    entry["created"] = server.value("created").toString();
    entry["modified"] = server.value("modified").toString();
    return entry;
}

QJsonArray toJsonArray(const QStringList &values) {
    QJsonArray array;
    for (const QString &value: values)
        array.append(value);
    return array;
}
}

EtsClient::EtsClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EtsClient::fetchServers(const QString &prefix) {
    QJsonObject body;
    body["prefix"] = prefix;

    m_base->post("ets", "list-servers", body, true,
         [this](const QJsonObject &response) {
             QVariantList servers;
             for (const QJsonArray array = response.value("servers").toArray(); const auto &value : array)
                 servers << serverToMap(value.toObject());
             emit serversLoaded(servers, static_cast<int>(servers.size()));
         },
         [this](const QString &message) {
             emit serversFailed(message);
         });
}

void EtsClient::createServer(const QString &serverId, const QString &protocol, const int port, const QString &bucket,
                             const QString &address, const QStringList &userIds, const QStringList &userGroups,
                             const int pasvMin, const int pasvMax) {
    QJsonObject body;
    body["serverId"] = serverId;
    body["protocol"] = protocol;
    body["port"] = port;
    body["bucket"] = bucket;
    body["address"] = address;
    body["userIds"] = toJsonArray(userIds);
    body["userGroups"] = toJsonArray(userGroups);
    body["pasvMin"] = pasvMin;
    body["pasvMax"] = pasvMax;

    m_base->post("ets", "create-server", body, true,
         [this](const QJsonObject &response) {
             emit serverCreated(response.value("serverId").toString());
             emit serversReload();
         },
         [this](const QString &message) {
             emit serverCreateFailed(message);
         });
}

void EtsClient::updateServer(const QString &serverId, const QVariantMap &changes) {
    QJsonObject body;
    body["serverId"] = serverId;
    // Only what the caller named: update-server treats an absent field as "leave it alone", so
    // forwarding the whole definition would overwrite settings nobody meant to touch.
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        if (it.value().typeId() == QMetaType::QStringList)
            body[it.key()] = toJsonArray(it.value().toStringList());
        else
            body[it.key()] = QJsonValue::fromVariant(it.value());
    }

    m_base->post("ets", "update-server", body, true,
         [this, serverId](const QJsonObject &response) {
             emit serverStateChanged(serverId, response.value("desiredState").toString());
             emit serversReload();
         },
         [this](const QString &message) {
             emit serverStateFailed(message);
         });
}

void EtsClient::deleteServer(const QString &serverId) {
    QJsonObject body;
    body["serverId"] = serverId;

    m_base->post("ets", "delete-server", body, true,
         [this](const QJsonObject &response) {
             emit serversReload();
         },
         [this](const QString &message) {
             emit serverStateFailed(message);
         });
}

void EtsClient::startServer(const QString &serverId) {
    QJsonObject body;
    body["serverId"] = serverId;

    m_base->post("ets", "start-server", body, true,
         [this, serverId](const QJsonObject &response) {
             emit serverStateChanged(serverId, response.value("desiredState").toString());
             emit serversReload();
         },
         [this](const QString &message) {
             emit serverStateFailed(message);
         });
}

void EtsClient::stopServer(const QString &serverId) {
    QJsonObject body;
    body["serverId"] = serverId;

    m_base->post("ets", "stop-server", body, true,
         [this, serverId](const QJsonObject &response) {
             emit serverStateChanged(serverId, response.value("desiredState").toString());
             emit serversReload();
         },
         [this](const QString &message) {
             emit serverStateFailed(message);
         });
}
