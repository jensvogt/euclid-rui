#include "EagClient.h"
#include "EuclidBaseClient.h"

namespace {
// Turns one "list-routes"/"get-route"/"update-route" entry into the map the QML pages read.
QVariantMap routeToMap(const QJsonObject &route) {
    QVariantMap entry;
    entry["routeId"] = route.value("routeId").toString();
    entry["ern"] = route.value("ern").toString();
    entry["accountId"] = route.value("accountId").toString();
    entry["region"] = route.value("region").toString();
    entry["namespace"] = route.value("namespace").toString();
    entry["path"] = route.value("path").toString();
    entry["applicationId"] = route.value("applicationId").toString();
    // The other kind of route: euclid itself rather than an application it runs. Exactly one of
    // these and applicationId is ever set - see Entity::EAG::Route::moduleTarget.
    entry["moduleTarget"] = route.value("moduleTarget").toString();
    entry["moduleAction"] = route.value("moduleAction").toString();
    // Empty means every method - the server stores "all" as no methods rather than as a list of
    // them, so a route written before a verb existed still answers for it.
    entry["methods"] = route.value("methods").toArray().toVariantList();
    entry["authentication"] = route.value("authentication").toString();
    entry["active"] = route.value("active").toBool();
    entry["created"] = route.value("created").toString();
    entry["modified"] = route.value("modified").toString();
    return entry;
}

QJsonArray toJsonArray(const QStringList &values) {
    QJsonArray array;
    for (const QString &value: values)
        array.append(value);
    return array;
}
}// namespace

EagClient::EagClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EagClient::fetchRoutes(const QString &prefix) {
    QJsonObject body;
    body["prefix"] = prefix;

    m_base->post("eag", "list-routes", body, true,
         [this](const QJsonObject &response) {
             QVariantList routes;
             for (const QJsonArray array = response.value("routes").toArray(); const auto &value: array)
                 routes << routeToMap(value.toObject());
             emit routesLoaded(routes, static_cast<int>(routes.size()));
         },
         [this](const QString &message) {
             emit routesFailed(message);
         });
}

void EagClient::fetchRoute(const QString &routeId) {
    QJsonObject body;
    body["routeId"] = routeId;

    m_base->post("eag", "get-route", body, true,
         [this, routeId](const QJsonObject &response) {
             emit routeLoaded(routeId, routeToMap(response));
         },
         [this](const QString &message) {
             emit routesFailed(message);
         });
}

void EagClient::createRoute(const QString &routeId, const QString &path, const QString &applicationId,
                            const QString &moduleTarget, const QString &moduleAction,
                            const QStringList &methods, const QString &authentication, const bool active) {
    QJsonObject body;
    body["routeId"] = routeId;
    body["path"] = path;
    // Only the one that applies is sent: the server reads "name either an application or a euclid
    // module" from which of the two is non-empty, so an empty string for the other is fine, but
    // sending both filled is refused.
    if (!applicationId.isEmpty()) {
        body["applicationId"] = applicationId;
    } else {
        body["moduleTarget"] = moduleTarget;
        body["moduleAction"] = moduleAction;
    }
    body["methods"] = toJsonArray(methods);
    body["authentication"] = authentication;
    body["active"] = active;

    m_base->post("eag", "create-route", body, true,
         [this, routeId](const QJsonObject &response) {
             emit routeCreated(routeId);
             emit routesReload();
         },
         [this](const QString &message) {
             emit routeCreateFailed(message);
         });
}

void EagClient::updateRoute(const QString &routeId, const QVariantMap &changes) {
    QJsonObject body;
    body["routeId"] = routeId;
    // Only what the caller named: update-route leaves out anything absent, so an omitted field
    // keeps the value it has rather than being reset.
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        const QVariant &value = it.value();
        if (value.typeId() == QMetaType::Bool) {
            body[it.key()] = value.toBool();
        } else if (value.typeId() == QMetaType::QStringList || value.typeId() == QMetaType::QVariantList) {
            body[it.key()] = toJsonArray(value.toStringList());
        } else {
            body[it.key()] = value.toString();
        }
    }

    m_base->post("eag", "update-route", body, true,
         [this, routeId](const QJsonObject &response) {
             emit routeUpdated(routeId, routeToMap(response));
             emit routesReload();
         },
         [this](const QString &message) {
             emit routeUpdateFailed(message);
         });
}

void EagClient::enableRoute(const QString &routeId) {
    updateRoute(routeId, QVariantMap{{QStringLiteral("active"), true}});
}

void EagClient::disableRoute(const QString &routeId) {
    updateRoute(routeId, QVariantMap{{QStringLiteral("active"), false}});
}

void EagClient::deleteRoute(const QString &routeId) {
    QJsonObject body;
    body["routeId"] = routeId;

    m_base->post("eag", "delete-route", body, true,
         [this, routeId](const QJsonObject &response) {
             emit routeDeleted(routeId);
             emit routesReload();
         },
         [this](const QString &message) {
             emit routeDeleteFailed(message);
         });
}
