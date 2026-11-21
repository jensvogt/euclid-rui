#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// EDS - the domain name service. Hosted zones and the record sets in them, managed over the
// module's API; the DNS port itself (1053 by default) is not something this client talks to.
// get-answer is how the RUI shows what that port would reply.
class EdsClient : public QObject {
    Q_OBJECT

public:
    explicit EdsClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // Zones of the current account and namespace, by name prefix. The server pages; it does not
    // sort, so the order is its own.
    Q_INVOKABLE void fetchZones(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10);
    Q_INVOKABLE void fetchZone(const QString &name);
    // `ttl` 0 takes the server's default (300). A zone's name is unique across the installation,
    // not just the account - a DNS question carries no account to choose between two.
    Q_INVOKABLE void createZone(const QString &name, int ttl = 0, const QString &description = QString());
    // Deletes the zone and every record in it.
    Q_INVOKABLE void deleteZone(const QString &name);

    // Record sets of one zone, optionally narrowed to one owner name and/or type.
    Q_INVOKABLE void fetchRecords(const QString &zone, const QString &name = QString(), const QString &type = QString(),
                                  int pageIndex = 0, int pageSize = 50);
    // Replaces the whole set of `type` at `name` - every value at once, so there is never a moment
    // with half the old values and half the new. `name` may be relative, fully qualified, "@" for
    // the apex or a wildcard such as "*.dev". `ttl` 0 takes the zone's.
    Q_INVOKABLE void putRecord(const QString &zone, const QString &name, const QString &type,
                               const QStringList &values, int ttl = 0);
    Q_INVOKABLE void deleteRecord(const QString &zone, const QString &name, const QString &type);

    // What the DNS port would answer for `name`/`type`, without a DNS client.
    Q_INVOKABLE void fetchAnswer(const QString &name, const QString &type = QStringLiteral("A"));

signals:
    void zonesLoaded(const QVariantList &zones, int total);
    void zonesFailed(const QString &message);
    void zonesReload();
    void zoneLoaded(const QVariantMap &zone);
    void zoneFailed(const QString &name, const QString &message);
    void zoneCreated(const QVariantMap &zone);
    void zoneCreateFailed(const QString &message);
    void zoneDeleted(const QString &name, int deletedRecords);
    void zoneDeleteFailed(const QString &message);

    void recordsLoaded(const QString &zone, const QVariantList &records, int total);
    void recordsFailed(const QString &zone, const QString &message);
    void recordPut(const QString &zone, const QVariantMap &record);
    void recordPutFailed(const QString &message);
    void recordDeleted(const QString &zone, const QString &name, const QString &type);
    void recordDeleteFailed(const QString &message);

    // {name, type, authoritative, zone, rcode, answers: [{name, type, ttl, value}], authority: [...]}
    void answerLoaded(const QVariantMap &answer);
    void answerFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
