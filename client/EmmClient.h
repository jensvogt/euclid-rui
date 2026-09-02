#pragma once

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <memory>

class EuclidBaseClient;
class QNetworkReply;
class QSaveFile;

// EMM (module manager) calls: live status of the euclid-mgr-supervised
// module processes (instance counts, uptime, autoscaling capacity), and the
// JSON export/import of the modules' own database collections.
class EmmClient : public QObject {
    Q_OBJECT

public:
    explicit EmmClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);
    ~EmmClient() override;

    Q_INVOKABLE void fetchModuleStatus(const QString &moduleName);

    // The whole module registry as euclid-mgr keeps it - the same "list-modules" call
    // fetchModuleStatus() makes, without narrowing it to one module. For a caller that wants the
    // shape of the installation rather than the detail of one module.
    Q_INVOKABLE void fetchModules();

    // The modules whose data can be exported and imported, in the order the UI should offer them.
    // Every module EMM has an export spec for except EMO, which is deliberately absent: it holds
    // nothing but monitoring samples, the one thing nobody wants restored on top of the live ones -
    // what to do with those is the operator's own decision, taken with mongodump rather than here.
    //
    // EKM is in the list and worth knowing about: its export carries the key material itself,
    // which is stored base64-encoded rather than encrypted. A file with ekm_key in it is as
    // sensitive as the database, and the dialog says so before writing one.
    Q_INVOKABLE static QStringList exportableModules();

    // Dumps each module's collections to one JSON file, in the shape "import" reads back.
    //
    // One request per module rather than the server's "all": a single response carrying every
    // module at once runs into the gateway's body limit, and per-module calls also give the UI
    // something honest to show progress with. Each module's collections are appended to the file
    // as its response arrives, so the whole export never has to sit in memory at once.
    //
    // includeObjects is the server's "full": the bulk child data (EQS/ENS messages, ESM objects)
    // that lives under the queues, topics and buckets. Off by default, and worth leaving off - it
    // dwarfs the definitions it hangs from.
    //
    // A passphrase, when given, seals the file: the server derives a key from it and each module's
    // data comes back encrypted, so what lands on disk is worth nothing without it. Required for
    // ekm, which the server refuses to export in the clear.
    Q_INVOKABLE void exportModules(const QStringList &modules, bool includeObjects, const QUrl &destination,
                                   const QString &passphrase);

    // Reads an export file and describes it without sending anything: what it holds, when it was
    // written, and how many documents each collection has. Returns {error} if it cannot be read.
    Q_INVOKABLE QVariantMap inspectImportFile(const QUrl &source) const;

    // Sends the collections of `modules` from `source` to the server, which upserts each document
    // by its "_id". Nothing is deleted: documents the file does not mention are left alone.
    Q_INVOKABLE void importFile(const QUrl &source, const QStringList &modules, const QString &passphrase);

    // Abandons whichever of the two is in flight. A gateway that accepts a request and then never
    // answers - one being redeployed underneath the application, say - would otherwise leave the
    // UI waiting on a transfer timeout with no way out.
    Q_INVOKABLE void cancel();

signals:
    void moduleStatusLoaded(const QString &moduleName, qint64 uptimeSeconds, int runningInstances, int maxInstances);
    void moduleStatusFailed(const QString &moduleName, const QString &message);
    // Each entry: {name, active, autoRestart, minInstances, maxInstances, runningInstances,
    // created, modified}. "active" is whether the module is enabled in the registry - whether
    // euclid-mgr should be running it at all - which is a different question from whether any
    // instance of it currently is. `total` is just the number of entries.
    void modulesLoaded(const QVariantList &modules, int total);
    void modulesFailed(const QString &message);

    // Emitted as each module's data is written, so a five-module export has five steps.
    void exportProgress(const QString &moduleName, int completed, int total);
    // collections is [{collection, documents}], one entry per collection written.
    void exportFinished(const QString &path, const QVariantList &collections, qint64 bytes);
    void exportFailed(const QString &message);

    // imported is [{collection, imported, failed}], skipped is [{collection, reason}] - both as
    // the server reported them.
    void importFinished(const QVariantList &imported, const QVariantList &skipped);
    void importFailed(const QString &message);

private:
    // One export at a time, carried between the per-module replies.
    struct ExportJob {
        QStringList pending;
        QStringList requested;
        int total = 0;
        bool full = false;
        QString passphrase;
        // Chosen by the server for the first module and reused for the rest, so one key opens
        // every frame in the file.
        QString salt;
        std::unique_ptr<QSaveFile> file;
        QVariantList collections;
        bool wroteHeader = false;
        bool wroteFrame = false;
    };

    // Writes the file's envelope. Takes the first module's response, which for a sealed archive is
    // where the key parameters come from.
    void writeHeader(const QJsonObject &response);
    void requestNextModule();
    void failExport(const QString &message);

    EuclidBaseClient *m_base;
    std::unique_ptr<ExportJob> m_export;
    // The request currently out, so it can be aborted. Held weakly: replies delete themselves.
    QPointer<QNetworkReply> m_reply;
};
