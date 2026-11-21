#include "EdsClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>

namespace {
// One zone as list-zones/get-zone/create-zone describe it.
QVariantMap zoneToMap(const QJsonObject &zone) {
    QVariantMap entry;
    entry["name"] = zone.value("name").toString();
    entry["ern"] = zone.value("ern").toString();
    entry["namespace"] = zone.value("namespace").toString();
    entry["ttl"] = zone.value("ttl").toInteger();
    entry["description"] = zone.value("description").toString();
    // Stored record sets only; the SOA and NS every zone answers with are not among them.
    entry["recordCount"] = zone.value("recordCount").toInteger();
    // The time of the zone's last change in seconds, which is what moves the SOA serial forward.
    entry["serial"] = zone.value("serial").toInteger();
    entry["created"] = zone.value("created").toString();
    entry["modified"] = zone.value("modified").toString();
    return entry;
}

// One record set: every value of one type at one (fully qualified) name.
QVariantMap recordToMap(const QJsonObject &record) {
    QVariantMap entry;
    entry["zone"] = record.value("zone").toString();
    entry["name"] = record.value("name").toString();
    entry["type"] = record.value("type").toString();
    entry["ttl"] = record.value("ttl").toInteger();
    const QVariantList values = record.value("values").toArray().toVariantList();
    entry["values"] = values;
    // Joined for the table, which shows one row per set.
    QStringList text;
    for (const QVariant &value: values) text << value.toString();
    entry["valuesText"] = text.join(QStringLiteral(", "));
    entry["created"] = record.value("created").toString();
    entry["modified"] = record.value("modified").toString();
    return entry;
}
}

EdsClient::EdsClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EdsClient::fetchZones(const QString &prefix, const int pageIndex, const int pageSize) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageIndex"] = pageIndex;
    body["pageSize"] = pageSize;

    m_base->post("eds", "list-zones", body, true,
         [this](const QJsonObject &response) {
             QVariantList zones;
             for (const QJsonValue &value: response.value("zones").toArray())
                 zones << zoneToMap(value.toObject());
             emit zonesLoaded(zones, response.value("total").toInt());
         },
         [this](const QString &message) { emit zonesFailed(message); });
}

void EdsClient::fetchZone(const QString &name) {
    QJsonObject body;
    body["name"] = name;
    m_base->post("eds", "get-zone", body, true,
         [this](const QJsonObject &response) { emit zoneLoaded(zoneToMap(response)); },
         [this, name](const QString &message) { emit zoneFailed(name, message); });
}

void EdsClient::createZone(const QString &name, const int ttl, const QString &description) {
    QJsonObject body;
    body["name"] = name;
    if (ttl > 0) body["ttl"] = ttl;
    if (!description.isEmpty()) body["description"] = description;

    m_base->post("eds", "create-zone", body, true,
         [this](const QJsonObject &response) {
             emit zoneCreated(zoneToMap(response));
             emit zonesReload();
         },
         [this](const QString &message) { emit zoneCreateFailed(message); });
}

void EdsClient::deleteZone(const QString &name) {
    QJsonObject body;
    body["name"] = name;
    m_base->post("eds", "delete-zone", body, true,
         [this, name](const QJsonObject &response) {
             emit zoneDeleted(name, response.value("deletedRecords").toInt());
             emit zonesReload();
         },
         [this](const QString &message) { emit zoneDeleteFailed(message); });
}

void EdsClient::fetchRecords(const QString &zone, const QString &name, const QString &type, const int pageIndex, const int pageSize) {
    QJsonObject body;
    body["zone"] = zone;
    if (!name.isEmpty()) body["name"] = name;
    if (!type.isEmpty()) body["type"] = type;
    body["pageIndex"] = pageIndex;
    body["pageSize"] = pageSize;

    m_base->post("eds", "list-records", body, true,
         [this, zone](const QJsonObject &response) {
             QVariantList records;
             for (const QJsonValue &value: response.value("records").toArray())
                 records << recordToMap(value.toObject());
             emit recordsLoaded(zone, records, response.value("total").toInt());
         },
         [this, zone](const QString &message) { emit recordsFailed(zone, message); });
}

void EdsClient::putRecord(const QString &zone, const QString &name, const QString &type, const QStringList &values, const int ttl) {
    QJsonObject body;
    body["zone"] = zone;
    body["name"] = name;
    body["type"] = type;
    if (ttl > 0) body["ttl"] = ttl;
    QJsonArray array;
    for (const QString &value: values) array.append(value);
    body["values"] = array;

    m_base->post("eds", "put-record", body, true,
         [this, zone](const QJsonObject &response) { emit recordPut(zone, recordToMap(response)); },
         [this](const QString &message) { emit recordPutFailed(message); });
}

void EdsClient::deleteRecord(const QString &zone, const QString &name, const QString &type) {
    QJsonObject body;
    body["zone"] = zone;
    body["name"] = name;
    body["type"] = type;
    m_base->post("eds", "delete-record", body, true,
         [this, zone, name, type](const QJsonObject &) { emit recordDeleted(zone, name, type); },
         [this](const QString &message) { emit recordDeleteFailed(message); });
}

void EdsClient::fetchAnswer(const QString &name, const QString &type) {
    QJsonObject body;
    body["name"] = name;
    body["type"] = type.isEmpty() ? QStringLiteral("A") : type;
    m_base->post("eds", "get-answer", body, true,
         [this](const QJsonObject &response) {
             QVariantMap answer = response.toVariantMap();
             emit answerLoaded(answer);
         },
         [this](const QString &message) { emit answerFailed(message); });
}
