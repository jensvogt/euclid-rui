#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

class EuclidBaseClient;

// ETS (transfer server) calls - the control plane for FTP/SFTP endpoints. ETS never speaks either
// protocol itself: it owns the server definitions, and start/stop only record a desired state that
// euclid-mgr's reconciler turns into a running euclid-ftp/euclid-sftp process. That is why every
// server carries both `state` (what is actually running) and `desiredState` (what was asked for);
// they differ for as long as the reconciler takes to catch up, or indefinitely if a server cannot
// start. Every action here is admin-only server-side.
class EtsClient : public QObject {
    Q_OBJECT

public:
    explicit EtsClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // "list-servers" takes a prefix but has no paging and returns no total, unlike the other
    // modules' list actions - every server is returned and the count is however many came back.
    Q_INVOKABLE void fetchServers(const QString &prefix = QString());

    // `bucket` is an ESM bucket *name*, resolved server-side at creation so a typo is reported now
    // rather than surfacing later as a server that runs but stores nothing. The server is created
    // STOPPED whatever else is passed; use startServer() afterwards.
    Q_INVOKABLE void createServer(const QString &serverId, const QString &protocol, int port, const QString &bucket,
                                  const QString &address = QStringLiteral("0.0.0.0"),
                                  const QStringList &userIds = QStringList(), const QStringList &userGroups = QStringList(),
                                  int pasvMin = 6000, int pasvMax = 6100);

    // Only the fields passed are changed server-side; this sends just the ones a caller names, so
    // an empty/zero argument means "leave it alone" rather than "set it to nothing".
    Q_INVOKABLE void updateServer(const QString &serverId, const QVariantMap &changes);

    Q_INVOKABLE void deleteServer(const QString &serverId);

    // Both only write desiredState - the server keeps reporting its old `state` until the
    // reconciler acts, which is why the UI shows the two separately.
    Q_INVOKABLE void startServer(const QString &serverId);
    Q_INVOKABLE void stopServer(const QString &serverId);

signals:
    // Each entry: {serverId, ern, accountId, region, protocol, address, port, bucketName,
    // bucketErn, userIds, userGroups, state, desiredState, hostKey, pasvMin, pasvMax, created,
    // modified}. `total` is just the number of entries - the action has no paging.
    void serversLoaded(const QVariantList &servers, int total);
    void serversFailed(const QString &message);
    void serversReload();
    void serverCreated(const QString &serverId);
    void serverCreateFailed(const QString &message);
    // Emitted for start/stop/update once the server has confirmed; carries the new desiredState so
    // a details page can show intent immediately instead of waiting for the next list.
    void serverStateChanged(const QString &serverId, const QString &desiredState);
    void serverStateFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
