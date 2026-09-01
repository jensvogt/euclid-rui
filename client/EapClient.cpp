#include "EapClient.h"
#include "EuclidBaseClient.h"

namespace {
// Turns one "list-applications"/"get-application" entry into the map the QML pages read.
QVariantMap applicationToMap(const QJsonObject &application) {
    QVariantMap entry;
    entry["applicationId"] = application.value("applicationId").toString();
    entry["ern"] = application.value("ern").toString();
    entry["accountId"] = application.value("accountId").toString();
    entry["region"] = application.value("region").toString();
    entry["runtime"] = application.value("runtime").toString();
    entry["bucketErn"] = application.value("bucketErn").toString();
    entry["artifactKey"] = application.value("artifactKey").toString();
    entry["command"] = application.value("command").toString();
    entry["arguments"] = application.value("arguments").toArray().toVariantList();
    entry["environment"] = application.value("environment").toObject().toVariantMap();
    // ERNs of the buckets and queues the application may act on; empty means unrestricted within
    // its own account.
    entry["resources"] = application.value("resources").toArray().toVariantList();
    entry["userId"] = application.value("userId").toString();
    entry["minInstances"] = application.value("minInstances").toInt();
    entry["maxInstances"] = application.value("maxInstances").toInt();
    entry["readyTimeoutMs"] = application.value("readyTimeoutMs").toInt();
    entry["state"] = application.value("state").toString();
    entry["desiredState"] = application.value("desiredState").toString();
    entry["instances"] = application.value("instances").toInt();
    entry["created"] = application.value("created").toString();
    entry["modified"] = application.value("modified").toString();
    return entry;
}

QJsonArray toJsonArray(const QStringList &values) {
    QJsonArray array;
    for (const QString &value: values)
        array.append(value);
    return array;
}

QJsonObject toJsonObject(const QVariantMap &values) {
    QJsonObject object;
    for (auto it = values.constBegin(); it != values.constEnd(); ++it)
        object[it.key()] = it.value().toString();
    return object;
}
}

EapClient::EapClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EapClient::fetchApplications(const QString &prefix) {
    QJsonObject body;
    body["prefix"] = prefix;

    m_base->post("eap", "list-applications", body, true,
         [this](const QJsonObject &response) {
             QVariantList applications;
             for (const QJsonArray array = response.value("applications").toArray(); const auto &value : array)
                 applications << applicationToMap(value.toObject());
             emit applicationsLoaded(applications, static_cast<int>(applications.size()));
         },
         [this](const QString &message) {
             emit applicationsFailed(message);
         });
}

void EapClient::createApplication(const QString &applicationId, const QString &runtime, const QString &bucket,
                                  const QString &artifact, const QString &userId, const QStringList &buckets,
                                  const QStringList &queues, const QString &command,
                                  const QStringList &arguments, const QVariantMap &environment,
                                  const int minInstances, const int maxInstances, const int readyTimeoutMs) {
    QJsonObject body;
    body["applicationId"] = applicationId;
    body["runtime"] = runtime;
    body["bucket"] = bucket;
    body["artifact"] = artifact;
    // Only sent when named: an empty "user" is what tells EAP to create the application its own
    // technical principal, and sending the key with an empty string says the same thing, but
    // leaving it out keeps the request honest about what was asked for.
    if (!userId.isEmpty())
        body["user"] = userId;
    body["buckets"] = toJsonArray(buckets);
    body["queues"] = toJsonArray(queues);
    body["command"] = command;
    body["arguments"] = toJsonArray(arguments);
    body["environment"] = toJsonObject(environment);
    body["minInstances"] = minInstances;
    body["maxInstances"] = maxInstances;
    body["readyTimeoutMs"] = readyTimeoutMs;

    m_base->post("eap", "create-application", body, true,
         [this](const QJsonObject &response) {
             emit applicationCreated(response.value("applicationId").toString());
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationCreateFailed(message);
         });
}

void EapClient::updateApplication(const QString &applicationId, const QVariantMap &changes) {
    QJsonObject body;
    body["applicationId"] = applicationId;
    // Only what the caller named: update-application leaves an absent field alone, so sending the
    // whole definition would overwrite settings nobody meant to touch.
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        if (it.value().typeId() == QMetaType::QStringList)
            body[it.key()] = toJsonArray(it.value().toStringList());
        else if (it.value().typeId() == QMetaType::QVariantMap)
            body[it.key()] = toJsonObject(it.value().toMap());
        else
            body[it.key()] = QJsonValue::fromVariant(it.value());
    }

    m_base->post("eap", "update-application", body, true,
         [this, applicationId](const QJsonObject &response) {
             emit applicationStateChanged(applicationId, response.value("desiredState").toString());
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationStateFailed(message);
         });
}

void EapClient::deleteApplication(const QString &applicationId) {
    QJsonObject body;
    body["applicationId"] = applicationId;

    m_base->post("eap", "delete-application", body, true,
         [this](const QJsonObject &response) {
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationStateFailed(message);
         });
}

void EapClient::startApplication(const QString &applicationId) {
    QJsonObject body;
    body["applicationId"] = applicationId;

    m_base->post("eap", "start-application", body, true,
         [this, applicationId](const QJsonObject &response) {
             emit applicationStateChanged(applicationId, response.value("desiredState").toString());
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationStateFailed(message);
         });
}

void EapClient::stopApplication(const QString &applicationId) {
    QJsonObject body;
    body["applicationId"] = applicationId;

    m_base->post("eap", "stop-application", body, true,
         [this, applicationId](const QJsonObject &response) {
             emit applicationStateChanged(applicationId, response.value("desiredState").toString());
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationStateFailed(message);
         });
}
