#include "EapClient.h"
#include "EuclidBaseClient.h"

namespace {
// Turns one "list-applications"/"get-application" entry into the map the QML pages read.
QVariantMap applicationToMap(const QJsonObject &application) {
    QVariantMap entry;
    entry["applicationId"] = application.value("applicationId").toString();
    // The name the manager actually runs this application under, which is not the one it is defined
    // under. An applicationId is unique within (account, namespace); a process pool, an EMM module
    // row, a data directory, a unix socket, a log channel and the technical principal named after
    // it are none of them scoped that way, so EAP issues a separate name - the id plus a random
    // suffix - once, and holds it for the application's whole life. Anything that has to find this
    // application outside its own definition looks for this, not for applicationId.
    //
    // Equal to applicationId on an application deployed before the field existed, which is what
    // those are still running as.
    entry["runtimeName"] = application.value("runtimeName").toString();
    entry["ern"] = application.value("ern").toString();
    entry["accountId"] = application.value("accountId").toString();
    // The other half of what identifies it. Every EAP action resolves an applicationId in the
    // namespace the request was made in, so this is the current one for anything in a listing -
    // but it is the definition's own, and it is what says where an application ended up after a
    // move.
    entry["namespace"] = application.value("namespace").toString();
    entry["region"] = application.value("region").toString();
    entry["runtime"] = application.value("runtime").toString();
    entry["bucketErn"] = application.value("bucketErn").toString();
    entry["artifactKey"] = application.value("artifactKey").toString();
    // What is deployed, and what it is made of: EAP refuses a redeploy unless the version moves on
    // and the artifact's checksum with it, so the two together say exactly which build is running.
    entry["version"] = application.value("version").toString();
    entry["md5Sum"] = application.value("md5Sum").toString();
    entry["command"] = application.value("command").toString();
    entry["arguments"] = application.value("arguments").toArray().toVariantList();
    entry["environment"] = application.value("environment").toObject().toVariantMap();
    // The placement constraint: labels a node must carry, all of them, for this application to be
    // put there. Empty means any node, including the manager's own host - which is what every
    // application on an installation with no workers has.
    entry["nodeLabels"] = application.value("nodeLabels").toObject().toVariantMap();
    // ERNs of the buckets and queues the application may act on; empty means unrestricted within
    // its own account.
    entry["resources"] = application.value("resources").toArray().toVariantList();
    entry["userId"] = application.value("userId").toString();
    // Whether that identity still exists. EAP checks it when an application is created and
    // never again, and a principal can be deleted or renamed underneath a definition that goes
    // on naming it - after which the application runs, authenticates as nobody and is refused
    // everything it calls, reporting whatever it happened to ask for first rather than who it
    // was asking as. Absent from a server older than the field, where true is the right guess:
    // it is what was assumed before anybody could ask.
    entry["userExists"] = application.value("userExists").toBool(true);
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

namespace {
// One node, from "list-nodes" or "get-node" - the server builds both with the same nodeToJson, so
// they are read in one place here too.
QVariantMap nodeToMap(const QJsonObject &node) {
    QVariantMap entry;
    entry["name"] = node.value("name").toString();
    // The EAM principal the worker registered as. The name belongs to whoever claimed it first, so
    // this is also what says a second worker cannot take it over.
    entry["principal"] = node.value("principal").toString();
    entry["labels"] = node.value("labels").toObject().toVariantMap();
    entry["cpuCount"] = node.value("cpuCount").toInteger();
    entry["version"] = node.value("version").toString();
    // What the worker's binary was built for, reported by the worker itself rather than configured
    // - so unlike a label it cannot disagree with the machine it is running on. Both empty for a
    // node registered by a worker older than the fields.
    entry["os"] = node.value("os").toString();
    entry["arch"] = node.value("arch").toString();
    entry["drained"] = node.value("drained").toBool();
    entry["live"] = node.value("live").toBool();
    entry["lastSeen"] = node.value("lastSeen").toString();
    return entry;
}
}// namespace

void EapClient::fetchNodes() {
    // No body: the server scopes the listing to the caller's account on its own, and there is
    // nothing to filter or page - an installation has as many nodes as it has hosts.
    m_base->post("eap", "list-nodes", QJsonObject(), true,
         [this](const QJsonObject &response) {
             QVariantList nodes;
             for (const QJsonArray array = response.value("nodes").toArray(); const auto &value : array)
                 nodes << nodeToMap(value.toObject());

             emit nodesLoaded(nodes, response.value("total").toInt(static_cast<int>(nodes.size())));
         },
         [this](const QString &message) {
             emit nodesFailed(message);
         });
}

void EapClient::fetchNode(const QString &node) {
    QJsonObject body;
    body["node"] = node;

    // Answers with the node itself rather than wrapping it in a field, unlike most of EAP - so the
    // response *is* the node, and there is nothing to unwrap.
    m_base->post("eap", "get-node", body, true,
         [this, node](const QJsonObject &response) {
             emit nodeLoaded(node, nodeToMap(response));
         },
         [this, node](const QString &message) {
             emit nodeLoadFailed(node, message);
         });
}

void EapClient::deleteNode(const QString &node) {
    QJsonObject body;
    body["node"] = node;

    m_base->post("eap", "delete-node", body, true,
         [this, node](const QJsonObject &) {
             emit nodeDeleted(node);
         },
         [this](const QString &message) {
             emit nodeDeleteFailed(message);
         });
}

void EapClient::setNodeDrained(const QString &node, const bool drained) {
    QJsonObject body;
    body["node"] = node;
    // Sent explicitly in both directions. The server reads an absent "drained" as true, because
    // that is what the action is called - but a request that says which way it means does not
    // depend on that, and undraining has to say so regardless.
    body["drained"] = drained;

    m_base->post("eap", "drain-node", body, true,
         [this, node](const QJsonObject &response) {
             emit nodeDrainChanged(node, response.value("drained").toBool());
         },
         [this](const QString &message) {
             emit nodeDrainFailed(message);
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

void EapClient::redeployApplication(const QString &applicationId, const QString &artifact, const QString &version,
                                    const bool force) {
    QJsonObject body;
    body["applicationId"] = applicationId;
    body["artifact"] = artifact;
    body["version"] = version;
    // Sent always rather than only when set: an absent field and a false one mean the same thing to
    // EAP, and a request that always carries it is one whose intent can be read off the wire.
    body["force"] = force;

    m_base->post("eap", "redeploy-application", body, true,
         [this, applicationId, artifact, version](const QJsonObject &response) {
             emit applicationRedeployed(applicationId, artifact, version);
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationRedeployFailed(message);
         });
}

void EapClient::scaleApplication(const QString &applicationId, const int minInstances, const int maxInstances) {
    QJsonObject body;
    body["applicationId"] = applicationId;
    // Left out rather than sent as -1: an absent bound is what tells EAP to keep the stored one,
    // and it checks the pair against whatever the other one then is - so naming only the ceiling
    // is still refused if it would fall below the floor already in the definition.
    if (minInstances >= 0)
        body["minInstances"] = minInstances;
    if (maxInstances >= 0)
        body["maxInstances"] = maxInstances;

    m_base->post("eap", "scale-application", body, true,
         [this, applicationId](const QJsonObject &response) {
             // What is stored now, read back from the definition the server answered with, rather
             // than what was asked for: both bounds come back even when one was sent.
             emit applicationScaled(applicationId, response.value("minInstances").toInt(),
                                    response.value("maxInstances").toInt());
             // The bounds are not the pool. The manager reconciles it on its next pass, so a
             // listing re-read now still shows the instance count it had.
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationScaleFailed(message);
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
