#include "EkmClient.h"
#include "EuclidBaseClient.h"

EkmClient::EkmClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EkmClient::fetchKeys(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ekm", "list-keys", body, true,
         [this](const QJsonObject &response) {
             QVariantList keys;
             for (const QJsonArray array = response.value("keys").toArray(); const auto &value : array) {
                 const QJsonObject key = value.toObject();
                 QVariantMap entry;
                 entry["name"] = key.value("name").toString();
                 entry["ern"] = key.value("ern").toString();
                 entry["algorithm"] = key.value("algorithm").toString();
                 entry["length"] = key.value("length").toInt();
                 entry["tags"] = key.value("tags").toObject().toVariantMap();
                 entry["status"] = key.value("status").toString();
                 entry["created"] = key.value("created").toString();
                 entry["modified"] = key.value("modified").toString();
                 keys << entry;
             }
             emit keysLoaded(keys, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit keysFailed(message);
         });
}

void EkmClient::createKey(const QString &algorithm, const int length) {
    QJsonObject body;
    body["algorithm"] = algorithm;
    body["length"] = length;

    m_base->post("ekm", "create-key", body, true,
         [this](const QJsonObject &response) {
             emit keyCreated(response.value("name").toString());
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyCreateFailed(message);
         });
}
