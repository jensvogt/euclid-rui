#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// EAG (API gateway) calls - the routing table in front of the EAP application pools. A route is a
// path prefix, what answers beneath it, and the methods and authentication it answers for; the
// gateway resolves an application's instances (and therefore their ports) when a request arrives,
// so a route says nothing about where anything is running.
//
// What answers is either an application euclid runs, or euclid itself: a route may instead name a
// module and one action on it (see Entity::EAG::Route::moduleTarget), which is how a browser can
// reach "login" without talking to a second origin. Exactly one of the two, never both - the
// server refuses anything else.
//
// Every action here is administrator-only server-side: publishing a path decides what the outside
// world can reach, which is not a per-user setting. The pages repeat that check so a non-admin is
// told rather than shown an empty table.
class EagClient : public QObject {
    Q_OBJECT

public:
    explicit EagClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // "list-routes" takes a prefix (matched against the routeId) but has no paging and returns no
    // total, like ETS's list-servers - every route comes back and the count is what arrived.
    Q_INVOKABLE void fetchRoutes(const QString &prefix = QString());
    Q_INVOKABLE void fetchRoute(const QString &routeId);

    // `methods` empty means every method, which is what the server stores for "all" - see
    // Entity::EAG::Route::methods. `authentication` is "NONE" or "EUCLID".
    //
    // Pass either `applicationId` or `moduleTarget` + `moduleAction`, leaving the other empty:
    // create-route refuses both and refuses neither, and a module route without an action would
    // have nothing to dispatch on.
    Q_INVOKABLE void createRoute(const QString &routeId, const QString &path, const QString &applicationId,
                                 const QString &moduleTarget = QString(), const QString &moduleAction = QString(),
                                 const QStringList &methods = QStringList(),
                                 const QString &authentication = QStringLiteral("NONE"),
                                 bool active = true);

    // Only the fields named are changed server-side, so a caller can send one of them without
    // restating the rest. Pass "methods" as a list, "active" as a bool.
    //
    // Send "applicationId" or "moduleTarget"/"moduleAction", never both: each clears the other
    // server-side, and naming both would leave which one wins up to the order they are read in.
    Q_INVOKABLE void updateRoute(const QString &routeId, const QVariantMap &changes);

    // Taking a route out of service without deleting it, which is what `active` is for: it goes
    // back exactly as it was. Both go through update-route.
    Q_INVOKABLE void enableRoute(const QString &routeId);
    Q_INVOKABLE void disableRoute(const QString &routeId);

    Q_INVOKABLE void deleteRoute(const QString &routeId);

signals:
    // Each entry: {routeId, ern, accountId, region, namespace, path, applicationId, moduleTarget,
    // moduleAction, methods, authentication, active, created, modified}. `total` is the number of
    // entries - the action has no paging.
    void routesLoaded(const QVariantList &routes, int total);
    void routesFailed(const QString &message);
    void routesReload();
    void routeLoaded(const QString &routeId, const QVariantMap &route);
    void routeCreated(const QString &routeId);
    void routeCreateFailed(const QString &message);
    // Emitted for update, enable and disable alike, carrying the route as it now stands so a
    // details page can show the change without waiting for the next listing.
    void routeUpdated(const QString &routeId, const QVariantMap &route);
    void routeUpdateFailed(const QString &message);
    void routeDeleted(const QString &routeId);
    void routeDeleteFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
