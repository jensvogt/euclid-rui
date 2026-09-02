#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// EAP (application) calls - the control plane for applications euclid runs. Like ETS next door,
// EAP runs nothing itself: it owns the definitions (which artifact in which bucket, which runtime,
// which EAM user it runs as, how far it may scale) and start/stop only write a desired state that
// euclid-mgr's reconciler turns into processes. So every application carries both `state` (what is
// actually running) and `desiredState` (what was asked for), and `instances` for how many are up.
// Every action here is admin-only server-side.
class EapClient : public QObject {
    Q_OBJECT

public:
    explicit EapClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // "list-applications" takes a prefix but has no paging and returns no total, same as ETS.
    Q_INVOKABLE void fetchApplications(const QString &prefix = QString());

    // `bucket` is an ESM bucket *name* and `artifact` an object key inside it; both are resolved
    // server-side at creation, so a typo is reported now rather than surfacing later as an
    // application that never starts. Created STOPPED whatever else is passed.
    //
    // `userId` is optional, and leaving it empty is the normal case: EAP then creates a technical
    // principal of its own ("app-<applicationId>") with its own access key and a grant for the
    // application's account and namespace, and deletes it again with the application - so an
    // application never has to borrow a person's credentials. Naming a user instead makes the
    // application act as that user, who must already exist and already have an access key.
    //
    // `buckets` and `queues` are *names*, resolved to ERNs server-side and stored as the
    // application's resource list. Leaving both empty means unrestricted within its own account;
    // naming any restricts it to those, which is what ESM and EQS then enforce.
    Q_INVOKABLE void createApplication(const QString &applicationId, const QString &runtime, const QString &bucket,
                                       const QString &artifact, const QString &userId = QString(),
                                       const QStringList &buckets = QStringList(), const QStringList &queues = QStringList(),
                                       const QString &command = QString(), const QStringList &arguments = QStringList(),
                                       const QVariantMap &environment = QVariantMap(),
                                       int minInstances = 1, int maxInstances = 1, int readyTimeoutMs = 30000);

    // Only the fields named are changed server-side, so this sends just those.
    Q_INVOKABLE void updateApplication(const QString &applicationId, const QVariantMap &changes);

    Q_INVOKABLE void deleteApplication(const QString &applicationId);

    // Deploys a build that is already in the application's bucket: it repoints the definition at
    // `artifact` and stamps it with `version`, and that stamp is the deployment - the manager reads
    // the changed definition as a new revision and restarts the running instances onto it within a
    // few seconds. Upload the artifact first (EsmClient::uploadObject), since EAP refuses a build
    // it cannot find.
    //
    // Refused server-side unless this is genuinely a new build: the version has to differ from the
    // deployed one, and so do the artifact's bytes. A version bump shipping identical bytes, or new
    // bytes under the version already running, are both deployments nobody could account for
    // afterwards. Deploying either on purpose is what updateApplication() is for.
    Q_INVOKABLE void redeployApplication(const QString &applicationId, const QString &artifact, const QString &version);

    // Both only write desiredState; the reconciler is what acts on it.
    Q_INVOKABLE void startApplication(const QString &applicationId);
    Q_INVOKABLE void stopApplication(const QString &applicationId);

signals:
    // Each entry: {applicationId, ern, accountId, region, runtime, bucketErn, artifactKey, command,
    // arguments, environment, resources, userId, minInstances, maxInstances, readyTimeoutMs,
    // state, desiredState, instances, created, modified}. `total` is just the number of entries.
    void applicationsLoaded(const QVariantList &applications, int total);
    void applicationsFailed(const QString &message);
    void applicationsReload();
    void applicationCreated(const QString &applicationId);
    void applicationCreateFailed(const QString &message);
    // Emitted for start/stop/update once the server confirms; carries the new desiredState so a
    // details page can show the intent without waiting for the next list.
    void applicationStateChanged(const QString &applicationId, const QString &desiredState);
    void applicationStateFailed(const QString &message);
    // The definition now names this artifact and this version, and the manager has been given a new
    // revision to restart onto.
    void applicationRedeployed(const QString &applicationId, const QString &artifact, const QString &version);
    void applicationRedeployFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
