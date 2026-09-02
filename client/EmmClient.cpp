#include "EmmClient.h"
#include "EuclidBaseClient.h"

#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QSaveFile>

namespace {
    // An export or import is one request that dumps or writes whole collections, so it gets far
    // longer than the default 15 seconds meant for calls that answer a page at a time. Not longer
    // still: this is an inactivity timeout, and what it really bounds is how long a gateway that
    // has stopped answering looks like one that is merely busy.
    constexpr int kTransferTimeoutMs = 2 * 60 * 1000;

    // Which module owns which collection, mirroring moduleExportSpecs() in the server's
    // EmmServer.cpp. Only used to describe an import file - the server does its own mapping, and
    // rejects any collection it does not recognise.
    QString moduleForCollection(const QString &collection) {
        static const QHash<QString, QString> owners{
                {QStringLiteral("eqs_queue"), QStringLiteral("eqs")},
                {QStringLiteral("eqs_message"), QStringLiteral("eqs")},
                {QStringLiteral("ens_topic"), QStringLiteral("ens")},
                {QStringLiteral("ens_subscription"), QStringLiteral("ens")},
                {QStringLiteral("ens_message"), QStringLiteral("ens")},
                {QStringLiteral("esm_bucket"), QStringLiteral("esm")},
                {QStringLiteral("esm_subscription"), QStringLiteral("esm")},
                {QStringLiteral("esm_object"), QStringLiteral("esm")},
                {QStringLiteral("eam_user"), QStringLiteral("eam")},
                {QStringLiteral("eam_usergroup"), QStringLiteral("eam")},
                {QStringLiteral("eam_account"), QStringLiteral("eam")},
                {QStringLiteral("eam_namespace"), QStringLiteral("eam")},
                {QStringLiteral("emm_module"), QStringLiteral("emm")},
                {QStringLiteral("emo_data"), QStringLiteral("emo")},
                {QStringLiteral("eap_application"), QStringLiteral("eap")},
                {QStringLiteral("ets_server"), QStringLiteral("ets")},
                {QStringLiteral("ekm_key"), QStringLiteral("ekm")},
        };
        return owners.value(collection);
    }
}// namespace

EmmClient::EmmClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

EmmClient::~EmmClient() = default;

QStringList EmmClient::exportableModules() {
    return {QStringLiteral("eam"), QStringLiteral("eap"), QStringLiteral("ekm"), QStringLiteral("emm"),
            QStringLiteral("ens"), QStringLiteral("eqs"), QStringLiteral("esm"), QStringLiteral("ets")};
}

void EmmClient::fetchModuleStatus(const QString &moduleName) {
    m_base->post("emm", "list-modules", QJsonObject{}, true,
         [this, moduleName](const QJsonObject &response) {
             for (const QJsonArray modules = response.value("modules").toArray(); const auto &moduleValue : modules) {
                 const QJsonObject module = moduleValue.toObject();
                 if (module.value("name").toString().compare(moduleName, Qt::CaseInsensitive) != 0)
                     continue;

                 int runningInstances = 0;
                 QDateTime earliestStart;
                 for (const QJsonArray instances = module.value("instances").toArray(); const auto &instanceValue : instances) {
                     const QJsonObject instance = instanceValue.toObject();
                     if (instance.value("state").toString() != "RUNNING")
                         continue;
                     ++runningInstances;
                     if (const QDateTime created = QDateTime::fromString(instance.value("created").toString(), Qt::ISODateWithMs); created.isValid() && (!earliestStart.isValid() || created < earliestStart))
                         earliestStart = created;
                 }

                 const qint64 uptimeSeconds = earliestStart.isValid()
                     ? earliestStart.secsTo(QDateTime::currentDateTimeUtc())
                     : 0;
                 const int maxInstances = module.value("maxInstances").toInt(1);
                 emit moduleStatusLoaded(moduleName, uptimeSeconds, runningInstances, maxInstances);
                 return;
             }
             emit moduleStatusFailed(moduleName, "Module \"" + moduleName + "\" was not found.");
         },
         [this, moduleName](const QString &message) {
             emit moduleStatusFailed(moduleName, message);
         });
}

void EmmClient::exportModules(const QStringList &modules, const bool includeObjects, const QUrl &destination,
                              const QString &passphrase) {
    if (m_export) {
        emit exportFailed(QStringLiteral("An export is already running."));
        return;
    }
    if (modules.isEmpty()) {
        emit exportFailed(QStringLiteral("Select at least one module to export."));
        return;
    }

    const QString path = destination.isLocalFile() ? destination.toLocalFile() : destination.toString();
    auto file = std::make_unique<QSaveFile>(path);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit exportFailed(QStringLiteral("Cannot write %1: %2").arg(path, file->errorString()));
        return;
    }

    m_export = std::make_unique<ExportJob>();
    m_export->pending = modules;
    m_export->requested = modules;
    m_export->total = static_cast<int>(modules.size());
    m_export->full = includeObjects;
    m_export->passphrase = passphrase;
    m_export->file = std::move(file);

    // A plain file gets its envelope now and the collections streamed into it. A sealed one cannot:
    // its header carries the salt and iteration count the server chose, which only the first
    // response knows - so writeHeader() runs once that arrives.
    if (passphrase.isEmpty())
        writeHeader({});

    requestNextModule();
}

void EmmClient::writeHeader(const QJsonObject &response) {
    QJsonArray moduleNames;
    for (const QString &module: m_export->requested)
        moduleNames.append(module);

    // The same envelope the server's own export produces, so an unencrypted file written here is
    // one "import" reads without knowing the difference. A sealed file adds the parameters needed
    // to derive the key again, and swaps the collections for the frames that hold them.
    QJsonObject envelope;
    envelope["modules"] = moduleNames;
    envelope["full"] = m_export->full;
    envelope["exportedAt"] = response.contains("exportedAt")
                                     ? response.value("exportedAt").toString()
                                     : QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    if (!m_export->passphrase.isEmpty()) {
        m_export->salt = response.value("salt").toString();
        envelope["encrypted"] = true;
        envelope["kdf"] = response.value("kdf");
        envelope["iterations"] = response.value("iterations");
        envelope["cipher"] = response.value("cipher");
        envelope["salt"] = m_export->salt;
    }

    // Serialized as an object and then opened up again, rather than assembled by hand: the values
    // in it are the server's, and quoting them correctly is not this function's business. What
    // follows the brace is written frame by frame as the modules answer.
    QByteArray header = QJsonDocument(envelope).toJson(QJsonDocument::Compact);
    header.chop(1);
    header += m_export->passphrase.isEmpty() ? ",\"collections\":{" : ",\"frames\":[";

    m_export->file->write(header);
    m_export->wroteHeader = true;
}

void EmmClient::requestNextModule() {
    if (!m_export)
        return;

    if (m_export->pending.isEmpty()) {
        m_export->file->write(m_export->passphrase.isEmpty() ? "}}" : "]}");
        const QString path = m_export->file->fileName();
        if (!m_export->file->commit()) {
            failExport(QStringLiteral("Cannot finish writing %1.").arg(path));
            return;
        }
        const QVariantList collections = m_export->collections;
        const qint64 bytes = QFile(path).size();
        m_export.reset();
        emit exportFinished(path, collections, bytes);
        return;
    }

    const QString module = m_export->pending.takeFirst();
    QJsonObject body;
    body["modules"] = QJsonArray{module};
    body["full"] = m_export->full;
    if (!m_export->passphrase.isEmpty()) {
        body["passphrase"] = m_export->passphrase;
        // Every frame in one file has to open with the same key, so the salt the first response
        // came back with is handed to the rest.
        if (!m_export->salt.isEmpty())
            body["salt"] = m_export->salt;
    }

    m_reply = m_base->post("emm", "export", body, true,
         [this, module](const QJsonObject &response) {
             if (!m_export)
                 return;

             if (!m_export->wroteHeader)
                 writeHeader(response);

             if (m_export->passphrase.isEmpty()) {
                 const QJsonObject collections = response.value("collections").toObject();
                 for (auto it = collections.constBegin(); it != collections.constEnd(); ++it) {
                     const QJsonArray documents = it.value().toArray();
                     // The key needs no escaping: collection names come from the server's own fixed
                     // list (eqs_queue, esm_object, ...), not from anything a user names.
                     QByteArray entry = m_export->wroteFrame ? ",\"" : "\"";
                     entry += it.key().toUtf8();
                     entry += "\":";
                     entry += QJsonDocument(documents).toJson(QJsonDocument::Compact);
                     m_export->file->write(entry);
                     m_export->wroteFrame = true;
                     m_export->collections.append(QVariantMap{{"collection", it.key()},
                                                              {"documents", documents.size()}});
                 }
             } else {
                 // One sealed frame per module, base64 as the server encoded it. What is inside is
                 // not this client's business - it has no key and no way to derive one.
                 QByteArray entry = m_export->wroteFrame ? ",\"" : "\"";
                 entry += response.value("data").toString().toUtf8();
                 entry += "\"";
                 m_export->file->write(entry);
                 m_export->wroteFrame = true;
                 // Counted per module rather than per collection: the counts are inside the frame.
                 m_export->collections.append(QVariantMap{{"collection", module}, {"documents", -1}});
             }

             emit exportProgress(module, m_export->total - static_cast<int>(m_export->pending.size()), m_export->total);
             requestNextModule();
         },
         [this, module](const QString &message) {
             failExport(QStringLiteral("%1: %2").arg(module, message));
         },
         kTransferTimeoutMs);
}

void EmmClient::cancel() {
    // Aborting makes the reply finish with OperationCanceledError, so the request's own error path
    // reports it - one route out, whether the gateway answered, timed out, or was given up on.
    if (m_reply)
        m_reply->abort();
}

void EmmClient::failExport(const QString &message) {
    if (m_export) {
        // Nothing half-written is left behind: QSaveFile only replaces the target on commit().
        m_export->file->cancelWriting();
        m_export.reset();
    }
    emit exportFailed(message);
}

QVariantMap EmmClient::inspectImportFile(const QUrl &source) const {
    const QString path = source.isLocalFile() ? source.toLocalFile() : source.toString();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {{"error", QStringLiteral("Cannot read %1: %2").arg(path, file.errorString())}};

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError)
        return {{"error", QStringLiteral("Not a JSON file: %1").arg(parseError.errorString())}};
    if (!document.isObject())
        return {{"error", QStringLiteral("Not a euclid export.")}};

    const QJsonObject root = document.object();
    const bool encrypted = root.value("encrypted").toBool();

    QVariantMap summary{{"path", path},
                        {"encrypted", encrypted},
                        {"exportedAt", root.value("exportedAt").toString()},
                        {"full", root.value("full").toBool()}};

    // A sealed file describes itself from its envelope and no further: which modules, when, and
    // how the key was derived. The counts are inside the frames, and stay there - this client has
    // no key, and the file is only opened where the passphrase is checked, on the server.
    if (encrypted) {
        if (!root.value("frames").isArray())
            return {{"error", QStringLiteral("Not a euclid export: sealed but with no frames.")}};

        QStringList modules;
        for (const QJsonValue &value: root.value("modules").toArray())
            modules.append(value.toString());
        modules.sort();

        summary.insert("modules", modules);
        summary.insert("frames", root.value("frames").toArray().size());
        summary.insert("documents", -1);
        summary.insert("collections", QVariantList{});
        return summary;
    }

    if (!root.contains("collections"))
        return {{"error", QStringLiteral("Not a euclid export: no \"collections\" object.")}};

    const QJsonObject collections = root.value("collections").toObject();
    QVariantList entries;
    QStringList modules;
    int documents = 0;
    for (auto it = collections.constBegin(); it != collections.constEnd(); ++it) {
        const QString module = moduleForCollection(it.key());
        const int count = it.value().toArray().size();
        documents += count;
        entries.append(QVariantMap{{"collection", it.key()},
                                   {"module", module.isEmpty() ? QStringLiteral("unknown") : module},
                                   {"documents", count},
                                   // EMO is never written from here and never restored from here;
                                   // an unrecognised collection is one the server would refuse.
                                   {"supported", !module.isEmpty() && exportableModules().contains(module)}});
        if (!module.isEmpty() && !modules.contains(module))
            modules.append(module);
    }
    modules.sort();

    summary.insert("documents", documents);
    summary.insert("modules", modules);
    summary.insert("collections", entries);
    return summary;
}

void EmmClient::importFile(const QUrl &source, const QStringList &modules, const QString &passphrase) {
    if (modules.isEmpty()) {
        emit importFailed(QStringLiteral("Select at least one module to import."));
        return;
    }

    const QString path = source.isLocalFile() ? source.toLocalFile() : source.toString();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        emit importFailed(QStringLiteral("Cannot read %1: %2").arg(path, file.errorString()));
        return;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        emit importFailed(QStringLiteral("Not a JSON file: %1").arg(parseError.errorString()));
        return;
    }
    const QJsonObject root = document.object();

    QJsonArray moduleNames;
    for (const QString &module: modules)
        moduleNames.append(module);

    QJsonObject body;
    if (root.value("encrypted").toBool()) {
        if (passphrase.isEmpty()) {
            emit importFailed(QStringLiteral("This export is sealed - it needs the passphrase it was written with."));
            return;
        }
        // Sent as it lies on disk, with the key parameters it was sealed under. Opening it is the
        // server's job: it holds the passphrase only for the length of the call, and this client
        // has no way to read a frame even if it wanted to.
        body["encrypted"] = true;
        body["kdf"] = root.value("kdf");
        body["iterations"] = root.value("iterations");
        body["cipher"] = root.value("cipher");
        body["salt"] = root.value("salt");
        body["frames"] = root.value("frames");
        body["passphrase"] = passphrase;
        body["modules"] = moduleNames;
    } else {
        // Sent already filtered rather than leaving it all to the server's own "modules" filter:
        // what the user deselected is then not on the wire at all. The filter goes along with it
        // anyway, so anything this does not recognise - a collection from a newer euclid - is
        // still refused by the server rather than written on the strength of its name.
        const QJsonObject collections = root.value("collections").toObject();
        QJsonObject selected;
        for (auto it = collections.constBegin(); it != collections.constEnd(); ++it) {
            if (modules.contains(moduleForCollection(it.key())))
                selected[it.key()] = it.value();
        }
        if (selected.isEmpty()) {
            emit importFailed(QStringLiteral("The file holds nothing for the selected modules."));
            return;
        }
        body["collections"] = selected;
        body["modules"] = moduleNames;
    }

    m_reply = m_base->postRaw("emm", "import", {}, QJsonDocument(body).toJson(QJsonDocument::Compact),
         [this](const QJsonObject &response) {
             QVariantList imported;
             const QJsonObject results = response.value("imported").toObject();
             for (auto it = results.constBegin(); it != results.constEnd(); ++it) {
                 const QJsonObject result = it.value().toObject();
                 imported.append(QVariantMap{{"collection", it.key()},
                                             {"imported", result.value("imported").toInt()},
                                             {"failed", result.value("failed").toInt()}});
             }

             QVariantList skipped;
             for (const QJsonArray array = response.value("skipped").toArray(); const auto &value : array) {
                 const QJsonObject entry = value.toObject();
                 skipped.append(QVariantMap{{"collection", entry.value("collection").toString()},
                                            {"reason", entry.value("reason").toString()}});
             }
             emit importFinished(imported, skipped);
         },
         [this](const QString &message) {
             emit importFailed(message);
         },
         kTransferTimeoutMs);
}
