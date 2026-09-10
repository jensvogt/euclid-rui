#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// EKV (key/value store) calls: tables of items, each identified by a partition key and optionally
// ordered within that partition by a sort key.
//
// Two things shape this class. First, an item is arbitrary JSON - an object of attributes, nested
// as deeply as the caller likes, with no type annotations to write and none to read back - so an
// item goes out as the text somebody typed and is parsed here, where a syntax error can be
// reported without a round trip. Second, a key is not: the table says what its key attributes are
// called and what type they are, so a key is built by the page that knows the table and arrives
// here as a map, typed the way QML typed it.
class EkvClient : public QObject {
    Q_OBJECT

public:
    explicit EkvClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // ── Tables ───────────────────────────────────────────────────────────────

    // Paged and sorted server-side. Every entry carries its item count, which EKV counts when
    // asked rather than keeping - so a listing of many tables is a query per table, and the page
    // size here is not free the way it is elsewhere.
    Q_INVOKABLE void fetchTables(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                 const QString &sortColumn = QStringLiteral("name"),
                                 const QString &sortDirection = QStringLiteral("asc"));

    // One table, with a freshly counted item count. What the details page re-reads: the count is
    // the only thing about a table that moves.
    Q_INVOKABLE void describeTable(const QString &name);

    // The key schema is fixed at creation - there is no call to change it, because every item is
    // stored under it. An empty sortKey makes a table whose partition key alone identifies an item.
    // Types are "string", "number" or "binary"; binary has no JSON spelling, so a binary key can be
    // declared but nothing can be written under one from here.
    Q_INVOKABLE void createTable(const QString &name, const QString &partitionKey,
                                 const QString &partitionKeyType = QStringLiteral("string"),
                                 const QString &sortKey = QString(),
                                 const QString &sortKeyType = QStringLiteral("string"));

    // Takes the items with it, and answers with how many went.
    Q_INVOKABLE void deleteTable(const QString &name);

    // ── Items ────────────────────────────────────────────────────────────────

    // Every item in the table, a page at a time, in no particular order - a scan is what to use
    // when the partition is not known. "scan" answers with a total; "query" does not, so a query
    // reports -1 and the page shows a count rather than a page count.
    Q_INVOKABLE void scanItems(const QString &table, int pageIndex = 0, int pageSize = 25);

    // One partition's items, in sort-key order. sortOperator is "" (the whole partition), or one of
    // eq, lt, le, gt, ge, between, begins-with; "between" is the one that reads sortUpper, and
    // "begins-with" only applies to a string sort key.
    Q_INVOKABLE void queryItems(const QString &table, const QVariant &partitionKey,
                                const QString &sortOperator = QString(),
                                const QVariant &sortValue = QVariant(),
                                const QVariant &sortUpper = QVariant(),
                                bool forward = true, int pageIndex = 0, int pageSize = 25);

    // The item as JSON text, parsed here. A put replaces whatever was under the key - there is no
    // partial update in EKV, so what is sent is the whole item.
    Q_INVOKABLE void putItem(const QString &table, const QString &itemJson);

    Q_INVOKABLE void getItem(const QString &table, const QVariantMap &key);
    Q_INVOKABLE void deleteItem(const QString &table, const QVariantMap &key);

signals:
    // Each entry: {name, ern, partitionKey, partitionKeyType, sortKey, sortKeyType, itemCount,
    // created, modified}. "sortKey" is empty for a table that has none.
    void tablesLoaded(const QVariantList &tables, int total);
    void tablesFailed(const QString &message);
    void tablesReload();

    void tableDescribed(const QString &name, const QVariantMap &table);
    void tableDescribeFailed(const QString &name, const QString &message);
    void tableCreated(const QString &name, const QVariantMap &table);
    void tableCreateFailed(const QString &message);
    void tableDeleted(const QString &name, int deletedItems);
    void tableDeleteFailed(const QString &message);

    // Each item is its attributes as a map, plus "_json" holding the same item as indented JSON -
    // a table reads the first, an editor the second. EKV's own "_created"/"_modified" are in there
    // alongside the attributes, and "_json" follows that convention: the store refuses '$' and '.'
    // in an attribute name but not an underscore, so this is a convention and not a guarantee.
    //
    // "total" is the table's item count for a scan and -1 for a query, which answers with what it
    // found and no count of what it did not.
    void itemsLoaded(const QString &table, const QVariantList &items, int count, int total);
    void itemsFailed(const QString &table, const QString &message);
    void itemsReload(const QString &table);

    void itemLoaded(const QString &table, const QVariantMap &item);
    void itemLoadFailed(const QString &table, const QString &message);
    void itemPut(const QString &table, const QVariantMap &item);
    void itemPutFailed(const QString &message);
    // "deleted" is false when the key named nothing, which is not an error server-side.
    void itemDeleted(const QString &table, bool deleted);
    void itemDeleteFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
