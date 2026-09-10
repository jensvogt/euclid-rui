#include "EkvClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonDocument>

namespace {

// Turns one "list-tables"/"describe-table"/"create-table" entry into the map the QML pages read.
// The key schema is flattened into four fields rather than nested, because that is how a table is
// read: which attribute, of which type.
QVariantMap tableToMap(const QJsonObject &table) {
    QVariantMap entry;
    entry["name"] = table.value("name").toString();
    entry["ern"] = table.value("ern").toString();
    entry["partitionKey"] = table.value("partitionKey").toString();
    entry["partitionKeyType"] = table.value("partitionKeyType").toString();
    // Empty for a table whose partition key alone identifies an item.
    entry["sortKey"] = table.value("sortKey").toString();
    entry["sortKeyType"] = table.value("sortKeyType").toString();
    // 64-bit deliberately: QJsonValue::toInt() abandons a number that will not fit an int and
    // returns its default, which would show a large table as an empty one.
    entry["itemCount"] = table.value("itemCount").toInteger();
    entry["created"] = table.value("created").toString();
    entry["modified"] = table.value("modified").toString();
    return entry;
}

// An item as the pages want it: its attributes to read one at a time, and the whole thing as
// indented JSON to show or edit. Both come from the one object the server answered with, so the
// text is what was stored rather than a re-serialization of a map that has already lost something.
QVariantMap itemToMap(const QJsonObject &item) {
    QVariantMap entry = item.toVariantMap();
    entry["_json"] = QString::fromUtf8(QJsonDocument(item).toJson(QJsonDocument::Indented)).trimmed();
    return entry;
}

// A key attribute value on its way out. QML types what it builds - a string stays a string, a
// number stays a number - and that is exactly the distinction EKV checks the key against, so the
// variant is converted rather than stringified.
QJsonObject keyToJson(const QVariantMap &key) {
    return QJsonObject::fromVariantMap(key);
}

}// namespace

EkvClient::EkvClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

// ── Tables ───────────────────────────────────────────────────────────────────

void EkvClient::fetchTables(const QString &prefix, const int pageIndex, const int pageSize,
                            const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ekv", "list-tables", body, true,
         [this](const QJsonObject &response) {
             QVariantList tables;
             for (const QJsonArray array = response.value("tables").toArray(); const auto &value: array)
                 tables << tableToMap(value.toObject());
             emit tablesLoaded(tables, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit tablesFailed(message);
         });
}

void EkvClient::describeTable(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("ekv", "describe-table", body, true,
         [this, name](const QJsonObject &response) {
             emit tableDescribed(name, tableToMap(response));
         },
         [this, name](const QString &message) {
             emit tableDescribeFailed(name, message);
         });
}

void EkvClient::createTable(const QString &name, const QString &partitionKey, const QString &partitionKeyType,
                            const QString &sortKey, const QString &sortKeyType) {
    QJsonObject body;
    body["name"] = name;
    body["partitionKey"] = partitionKey;
    body["partitionKeyType"] = partitionKeyType;
    // Sent even when empty: an empty sortKey is what says the table has none, and the type beside
    // it is then ignored server-side rather than being an error.
    body["sortKey"] = sortKey;
    body["sortKeyType"] = sortKeyType;

    m_base->post("ekv", "create-table", body, true,
         [this, name](const QJsonObject &response) {
             emit tableCreated(name, tableToMap(response));
             emit tablesReload();
         },
         [this](const QString &message) {
             emit tableCreateFailed(message);
         });
}

void EkvClient::deleteTable(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("ekv", "delete-table", body, true,
         [this, name](const QJsonObject &response) {
             emit tableDeleted(name, response.value("deletedItems").toInt());
             emit tablesReload();
         },
         [this](const QString &message) {
             emit tableDeleteFailed(message);
         });
}

// ── Items ────────────────────────────────────────────────────────────────────

void EkvClient::scanItems(const QString &table, const int pageIndex, const int pageSize) {
    QJsonObject body;
    body["table"] = table;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;

    m_base->post("ekv", "scan", body, true,
         [this, table](const QJsonObject &response) {
             QVariantList items;
             for (const QJsonArray array = response.value("items").toArray(); const auto &value: array)
                 items << itemToMap(value.toObject());
             emit itemsLoaded(table, items, response.value("count").toInt(), response.value("total").toInt());
         },
         [this, table](const QString &message) {
             emit itemsFailed(table, message);
         });
}

void EkvClient::queryItems(const QString &table, const QVariant &partitionKey, const QString &sortOperator,
                           const QVariant &sortValue, const QVariant &sortUpper, const bool forward,
                           const int pageIndex, const int pageSize) {
    QJsonObject body;
    body["table"] = table;
    body["partitionKey"] = QJsonValue::fromVariant(partitionKey);
    // An empty operator is the whole partition, which is what the server reads as "None" - so it is
    // sent as it is rather than omitted.
    body["sortOperator"] = sortOperator;
    body["sortValue"] = QJsonValue::fromVariant(sortValue);
    body["sortUpper"] = QJsonValue::fromVariant(sortUpper);
    body["forward"] = forward;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;

    m_base->post("ekv", "query", body, true,
         [this, table](const QJsonObject &response) {
             QVariantList items;
             for (const QJsonArray array = response.value("items").toArray(); const auto &value: array)
                 items << itemToMap(value.toObject());
             // No total: a query answers with what it found in the partition and counts nothing
             // beyond it. -1 is what tells the page to say "found n" rather than "n of m".
             emit itemsLoaded(table, items, response.value("count").toInt(), -1);
         },
         [this, table](const QString &message) {
             emit itemsFailed(table, message);
         });
}

void EkvClient::putItem(const QString &table, const QString &itemJson) {
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(itemJson.toUtf8(), &parseError);
    // Refused here rather than sent: the server would answer the same way, and a syntax error is
    // worth pointing at the character it is on, which only the parse that failed knows.
    if (parseError.error != QJsonParseError::NoError) {
        emit itemPutFailed(QStringLiteral("The item is not valid JSON: %1 (at character %2)")
                                   .arg(parseError.errorString())
                                   .arg(parseError.offset));
        return;
    }
    if (!document.isObject()) {
        emit itemPutFailed(QStringLiteral("An item has to be a JSON object of attributes."));
        return;
    }

    QJsonObject body;
    body["table"] = table;
    body["item"] = document.object();

    m_base->post("ekv", "put-item", body, true,
         [this, table](const QJsonObject &response) {
             emit itemPut(table, itemToMap(response));
             emit itemsReload(table);
         },
         [this](const QString &message) {
             emit itemPutFailed(message);
         });
}

void EkvClient::getItem(const QString &table, const QVariantMap &key) {
    QJsonObject body;
    body["table"] = table;
    body["key"] = keyToJson(key);

    m_base->post("ekv", "get-item", body, true,
         [this, table](const QJsonObject &response) {
             emit itemLoaded(table, itemToMap(response));
         },
         [this, table](const QString &message) {
             emit itemLoadFailed(table, message);
         });
}

void EkvClient::deleteItem(const QString &table, const QVariantMap &key) {
    QJsonObject body;
    body["table"] = table;
    body["key"] = keyToJson(key);

    m_base->post("ekv", "delete-item", body, true,
         [this, table](const QJsonObject &response) {
             emit itemDeleted(table, response.value("deleted").toBool());
             emit itemsReload(table);
         },
         [this](const QString &message) {
             emit itemDeleteFailed(message);
         });
}
