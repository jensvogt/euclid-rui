#include "EapClient.h"
#include "EuclidBaseClient.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>

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
    // Whether this is something that stays up or something that finishes: PROCESS is held at its
    // instance count and restarted on an exit, a JOB runs to completion and nothing restarts it,
    // and UNKNOWN is what a value a newer euclid wrote reads as. PROCESS when the server does not
    // send it at all, which is the same default the definition itself carries - everything that
    // existed before the field is one.
    entry["type"] = application.value("type").toString(QStringLiteral("PROCESS"));
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

// ── Infrastructure declarations ──────────────────────────────────────────────
// A mirror of Database::Entity::EAP::Infrastructure in the euclid backend, as far as merging goes.
// The server is still the authority: it re-reads this document when it applies it and refuses what
// it does not accept. What is done here is what only the client can do - reading local files and
// putting them together - plus the errors worth having before an upload rather than after one.

// Spelled plural, the way they appear in the file. A kind that is not one of these is an error
// rather than an ignored section: the silent no-op is how somebody's queues never get created.
const QStringList kResourceKinds{QStringLiteral("queues"), QStringLiteral("topics"), QStringLiteral("buckets")};

struct DeclaredResource {
    QString kind;
    QString name;
    QString owner;
    QStringList access;
};

struct Declaration {
    QString applicationId;
    QList<DeclaredResource> creates;
    QList<DeclaredResource> uses;
};

// One entry of one section. `error` non-empty means the rest is meaningless.
QString readResource(const QString &kind, const QJsonValue &value, DeclaredResource &resource) {
    if (!value.isObject())
        return kind + " entry is not an object";
    const QJsonObject object = value.toObject();

    resource.kind = kind;
    resource.name = object.value("name").toString();
    if (resource.name.isEmpty())
        return kind + " entry has no name";
    resource.owner = object.value("owner").toString();

    // A string or an array of them, because one level is the common case and writing it as a
    // one-element array would be noise.
    const QJsonValue access = object.value("access");
    if (access.isString()) {
        resource.access << access.toString();
    } else if (access.isArray()) {
        for (const QJsonArray array = access.toArray(); const auto &entry: array) {
            if (!entry.isString())
                return resource.name + ": access entries have to be strings";
            resource.access << entry.toString();
        }
    } else if (!access.isUndefined() && !access.isNull()) {
        return resource.name + ": access has to be a string or an array of strings";
    }
    return {};
}

// One file. The version is refused rather than defaulted: a file that does not say which schema it
// is written against is not one to guess at and apply to somebody's installation.
QString readDeclaration(const QJsonDocument &document, Declaration &declaration) {
    if (!document.isObject())
        return "declaration is not a JSON object";
    const QJsonObject object = document.object();

    if (object.value("version").toInt(0) != 1)
        return "version has to be 1";
    declaration.applicationId = object.value("applicationId").toString();

    for (const auto &section: {QStringLiteral("creates"), QStringLiteral("uses")}) {
        const QJsonValue sectionValue = object.value(section);
        if (sectionValue.isUndefined())
            continue;
        if (!sectionValue.isObject())
            return section + " is not an object";

        const QJsonObject kinds = sectionValue.toObject();
        for (auto it = kinds.constBegin(); it != kinds.constEnd(); ++it) {
            if (!kResourceKinds.contains(it.key()))
                return section + ": unknown resource kind \"" + it.key() + "\"";
            if (!it.value().isArray())
                return it.key() + " has to be an array";

            for (const QJsonArray entries = it.value().toArray(); const auto &entry: entries) {
                DeclaredResource resource;
                if (const auto error = readResource(it.key(), entry, resource); !error.isEmpty())
                    return section + ": " + error;

                if (section == QLatin1String("creates")) {
                    // Not wrong so much as meaningless, and ignoring it would leave somebody
                    // believing they had narrowed their own access to something they own outright.
                    if (!resource.access.isEmpty())
                        return "creates: " + resource.name + " names an access level; owning it is the access";
                    declaration.creates << resource;
                } else {
                    // Which levels exist is the server's table, not this one's - but an entry that
                    // names none cannot mean anything on any table.
                    if (resource.access.isEmpty())
                        return "uses: " + resource.name + " names no access";
                    declaration.uses << resource;
                }
            }
        }
    }
    return {};
}

// The document as the sidecar object holds it. Sorted by kind and then name so that the same files
// produce the same bytes however they were listed.
QJsonObject writeDeclaration(const Declaration &declaration) {
    const auto section = [](QList<DeclaredResource> resources) {
        std::sort(resources.begin(), resources.end(), [](const DeclaredResource &a, const DeclaredResource &b) {
            return a.kind != b.kind ? a.kind < b.kind : a.name < b.name;
        });
        QJsonObject out;
        for (const auto &resource: resources) {
            QJsonObject entry{{"name", resource.name}};
            if (!resource.owner.isEmpty())
                entry["owner"] = resource.owner;
            if (!resource.access.isEmpty())
                entry["access"] = toJsonArray(resource.access);
            QJsonArray kind = out.value(resource.kind).toArray();
            kind.append(entry);
            out[resource.kind] = kind;
        }
        return out;
    };

    QJsonObject out{{"version", 1}};
    if (!declaration.applicationId.isEmpty())
        out["applicationId"] = declaration.applicationId;
    if (!declaration.creates.isEmpty())
        out["creates"] = section(declaration.creates);
    if (!declaration.uses.isEmpty())
        out["uses"] = section(declaration.uses);
    return out;
}

// The files to read: the *.json of a folder, or the files themselves. Name order either way, so
// that a second run over the same selection reads them the same way and an error about one file
// means the same file next time.
QStringList declarationFiles(const QList<QUrl> &sources, QString &error) {
    QStringList paths;
    for (const QUrl &source: sources) {
        const QString path = source.isLocalFile() ? source.toLocalFile() : source.toString();
        if (QFileInfo(path).isDir()) {
            const QDir folder(path);
            const auto entries = folder.entryList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);
            if (entries.isEmpty()) {
                error = "no .json files in " + folder.dirName();
                return {};
            }
            for (const QString &entry: entries)
                paths << folder.filePath(entry);
        } else {
            paths << path;
        }
    }
    paths.sort();
    return paths;
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

    // What the node is actually running, which only "get-node" carries: a listing leaves it out
    // rather than walking every module pool once per row. So an entry out of fetchNodes() has none
    // of these - which is not the same as a node running nothing, and is why the details page asks
    // for its node by name instead of picking it out of the list it came from.
    QVariantList applications;
    for (const QJsonArray array = node.value("applications").toArray(); const auto &value: array) {
        const QJsonObject application = value.toObject();
        QVariantMap placement;
        placement["applicationId"] = application.value("applicationId").toString();
        // The pool name, which is what the instances, the data directory and the log channel on
        // this host are called - so it is the name to look for once you are on the machine.
        placement["runtimeName"] = application.value("runtimeName").toString();
        placement["namespace"] = application.value("namespace").toString();
        placement["runtime"] = application.value("runtime").toString();
        // Slots this node holds, and how many of them are actually serving. Both, because a node
        // holding slots that run nothing is the state worth seeing.
        placement["instances"] = application.value("instances").toInteger();
        placement["running"] = application.value("running").toInteger();
        applications << placement;
    }
    entry["applications"] = applications;
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
                                  const QString &artifact, const QString &userId, const QString &type,
                                  const QString &schedule, const QStringList &buckets,
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
    // Both left out when empty, for the same reason: the server's own defaults are the ones to
    // apply, and a "type" of "" is a word it would have to refuse. An empty schedule is a job
    // started on demand, which is what sending nothing says.
    if (!type.isEmpty())
        body["type"] = type;
    if (!schedule.isEmpty())
        body["schedule"] = schedule;
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
             const auto created = response.value("applicationId").toString();
             emit applicationCreated(created);
             // create-application applies the declaration beside the artifact as part of deploying,
             // and reports what that did under "infrastructure". Worth passing on rather than
             // dropping: a declaration that could not be applied does not fail the create - EAP
             // refuses to stop a release over a JSON typo - so without this the application would
             // appear with none of the queues it asked for and nothing would have said why.
             reportInfrastructure(created, response.value("infrastructure").toObject());
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

// The outcome of applying a declaration, as both actions that do it report it: apply-infrastructure
// answers with the fields at the top level, create-application nests the same ones under
// "infrastructure". An "error" there is a declaration that could not be read or applied - which
// create-application reports without failing, so it has to reach a page as a failure of its own.
void EapClient::reportInfrastructure(const QString &applicationId, const QJsonObject &infrastructure) {
    if (infrastructure.isEmpty())
        return;

    const auto message = infrastructure.value("error").toString();
    if (!message.isEmpty()) {
        emit infrastructureApplyFailed(message);
        return;
    }

    const auto ernList = [&infrastructure](const QString &name) {
        QStringList erns;
        for (const QJsonArray array = infrastructure.value(name).toArray(); const auto &value: array)
            erns << value.toString();
        return erns;
    };
    emit infrastructureApplied(applicationId, infrastructure.value("declared").toBool(),
                               ernList("created"), ernList("deleted"),
                               ernList("granted"), ernList("revoked"));
}

QVariantMap EapClient::mergeDeclaration(const QList<QUrl> &sources, const QString &applicationId) const {
    const auto refuse = [](const QString &message) {
        return QVariantMap{{"error", message}};
    };

    QString error;
    const QStringList paths = declarationFiles(sources, error);
    if (!error.isEmpty())
        return refuse(error);
    if (paths.isEmpty())
        return refuse(QStringLiteral("no declaration files were picked"));

    QList<Declaration> declarations;
    QStringList fileNames;
    for (const QString &path: paths) {
        QFile file(path);
        const QString name = QFileInfo(path).fileName();
        if (!file.open(QIODevice::ReadOnly))
            return refuse(name + " could not be read");

        QJsonParseError parse{};
        const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parse);
        if (parse.error != QJsonParseError::NoError)
            return refuse(name + " is not JSON: " + parse.errorString());

        Declaration declaration;
        if (const auto message = readDeclaration(document, declaration); !message.isEmpty())
            return refuse(name + ": " + message);

        declarations << declaration;
        fileNames << name;
    }

    Declaration merged;
    // One claim, or none. Two files naming different applications is refused rather than settled by
    // taking the last: picking one silently is how a declaration ends up attributed to an
    // application that does not own it, which is what the field exists to prevent.
    for (const auto &declaration: declarations) {
        if (declaration.applicationId.isEmpty())
            continue;
        if (!merged.applicationId.isEmpty() && merged.applicationId != declaration.applicationId) {
            return refuse("these files disagree about whose they are: \"" + merged.applicationId
                          + "\" and \"" + declaration.applicationId + "\"");
        }
        merged.applicationId = declaration.applicationId;
    }

    QSet<QString> seen;
    for (const auto &declaration: declarations) {
        for (const auto &resources: {declaration.creates, declaration.uses}) {
            for (const auto &resource: resources) {
                // Across both sections: owning a queue and declaring that you use it are two
                // statements about the same resource, and only one of them can be the one that
                // counts.
                if (seen.contains(resource.kind + '/' + resource.name))
                    return refuse("declared twice: " + resource.kind + " \"" + resource.name + "\"");
                seen.insert(resource.kind + '/' + resource.name);
            }
        }
        merged.creates << declaration.creates;
        merged.uses << declaration.uses;
    }

    // Stamped, so that from here on the document says which application it is for rather than
    // relying on the key it happens to be stored under. A file that names another application is
    // refused here as well as by the server: its resources would be recorded against this one, and
    // this one's next reconcile would delete them.
    //
    // An empty applicationId asks for neither, which is what a dialog reading files before the
    // application has been named needs: the merge is what it shows, and the stamped document is
    // asked for again once there is a name to stamp it with.
    if (!applicationId.isEmpty()) {
        if (merged.applicationId.isEmpty())
            merged.applicationId = applicationId;
        if (merged.applicationId != applicationId) {
            return refuse("these files declare \"" + merged.applicationId + "\", not \"" + applicationId + "\"");
        }
    }

    return QVariantMap{{"error", QString()},
                       {"document", QString::fromUtf8(QJsonDocument(writeDeclaration(merged)).toJson(QJsonDocument::Indented))},
                       {"fileNames", fileNames},
                       {"creates", static_cast<int>(merged.creates.size())},
                       {"uses", static_cast<int>(merged.uses.size())}};
}

void EapClient::applyInfrastructure(const QString &applicationId) {
    QJsonObject body;
    body["applicationId"] = applicationId;

    m_base->post("eap", "apply-infrastructure", body, true,
         [this, applicationId](const QJsonObject &response) {
             // The same fields, one level up: this action is about nothing else, so it answers with
             // them directly rather than under a key.
             reportInfrastructure(applicationId, response);
             // The application's own definition is untouched - applying a declaration deliberately
             // does not stamp it - but what it owns has just been created or deleted, and the
             // resource list on the row is read from the grants this rewrote.
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit infrastructureApplyFailed(message);
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

void EapClient::restartApplication(const QString &applicationId) {
    QJsonObject body;
    body["applicationId"] = applicationId;

    m_base->post("eap", "restart-application", body, true,
         [this, applicationId](const QJsonObject &response) {
             emit applicationRestarted(applicationId, response.value("instances").toInt());
             // Re-read rather than patched: what this wrote is the definition's stamp, so the row's
             // "Modified" has moved - and the state and instance count move with the pool over the
             // next passes, which only another listing says.
             emit applicationsReload();
         },
         [this](const QString &message) {
             emit applicationRestartFailed(message);
         });
}
