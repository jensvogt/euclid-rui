#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
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
    // Refused server-side unless the artifact's bytes differ from the deployed ones: a build that
    // is byte for byte the one already running is a restart that changes nothing, and a deployment
    // nobody could account for afterwards.
    //
    // force overrides that refusal, for when redeploying the same bytes is the point - an artifact
    // that was deleted and is being put back, or a host that lost its copy of the build. The server
    // logs the reason it was told to ignore, so a pool that restarted onto the same build is still
    // answerable for afterwards.
    Q_INVOKABLE void redeployApplication(const QString &applicationId, const QString &artifact, const QString &version,
                                         bool force = false);

    // The autoscaler's bounds, and the call to change them. Either may be left as it stands by
    // passing -1, which is what lets a ceiling be raised without naming the floor it has to clear.
    //
    // Not updateApplication(), which takes the same two fields and corrects them without saying
    // so: it clamps a floor to at least 1 and lifts a ceiling to meet the floor, so a request
    // nobody could have meant came back as a success carrying numbers nobody asked for.
    // scale-application refuses those instead and says why - a floor of 0 is stop-application's
    // job, and a floor above the ceiling is a mistake worth hearing about rather than a pool
    // silently scaled to something else.
    //
    // Administrators only, unlike the reads on this client.
    Q_INVOKABLE void scaleApplication(const QString &applicationId, int minInstances = -1, int maxInstances = -1);

    // Merges declaration files into the single document that is stored beside the artifact.
    //
    // `sources` is either the files themselves or one folder, in which case every *.json in it is
    // read - the two ways the CLI's "eap deploy-infrastructure --dir" is reached from a dialog. How
    // a declaration is split across files is the author's business, so they are merged by section
    // and kind rather than by filename, and two files naming the same resource is refused rather
    // than resolved: whichever a merge preferred, the other author would have been overruled
    // without being told.
    //
    // Structure only. Whether "readwrite" is an access level queues have, and whether a "uses"
    // entry names something that exists, are the server's to answer - it re-reads this document
    // when it applies it, and mirroring its permission table here would be a copy that drifts.
    //
    // `applicationId` empty merges without stamping the document or checking whose it is, which is
    // what a dialog needs to show a selection before the application has been named; the stamped
    // document is asked for again with the name, once there is one.
    //
    // Returns {error, document, fileNames, creates, uses}: `error` empty means `document` is the
    // JSON to store and `fileNames` the files it was made of - a folder expanded into them - and
    // non-empty means nothing was merged and it says why, naming the file.
    Q_INVOKABLE QVariantMap mergeDeclaration(const QList<QUrl> &sources, const QString &applicationId) const;

    // Applies the declaration stored beside the application's artifact - the object called
    // "<applicationId>.euclid.json" in the application's own bucket, which names the queues and
    // topics the application owns and the resources somebody else owns that it has to reach.
    //
    // A full reconcile, not an addition: what the declaration names is created, what this
    // application owned and no longer declares is *deleted* - with a queue's messages and a
    // bucket's objects - and its access grants are replaced with exactly the ones the file asks
    // for. That is why it answers with what it did rather than simply succeeding.
    //
    // Create, update and redeploy apply it in passing; this is the way to apply it on its own,
    // after the declaration has been uploaded. Nothing about the running processes changes, and
    // the definition is deliberately not stamped - the manager would read that as a new revision
    // and restart the pool for a change that does not concern it.
    //
    // The RUI's half of the CLI's "eap deploy-infrastructure", which merges a folder of
    // declaration files, uploads the result and then calls this. Uploading is ESM's job here too
    // (EsmClient::uploadObject), so what is left is this.
    //
    // Administrators only.
    Q_INVOKABLE void applyInfrastructure(const QString &applicationId);

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
    // What applying the declaration did. `declared` is false for an application that has no
    // declaration stored at all, which is not an error - most do not - and the four lists are then
    // empty. They are ERNs: what was created, what was deleted because the file no longer names
    // it, and the resources access was granted on and revoked from.
    void infrastructureApplied(const QString &applicationId, bool declared, const QStringList &created,
                               const QStringList &deleted, const QStringList &granted, const QStringList &revoked);
    // A declaration that could not be read or could not be applied: malformed JSON, an access level
    // that is not one of the known ones, a "uses" entry naming something that does not exist, or a
    // file that declares a different application than the one it is stored under.
    void infrastructureApplyFailed(const QString &message);
    // The bounds as the server stored them, which is both of them even when only one was sent.
    void applicationScaled(const QString &applicationId, int minInstances, int maxInstances);
    // Carries the server's own wording: it is the side that decides what a bound may be, and it
    // names the way out - stopping the application rather than scaling it to nothing.
    void applicationScaleFailed(const QString &message);

private:
    // Turns the "infrastructure" block of an answer into infrastructureApplied/
    // infrastructureApplyFailed. Shared because two actions carry it: apply-infrastructure, which
    // is about nothing else, and create-application, which applies the declaration in passing.
    void reportInfrastructure(const QString &applicationId, const QJsonObject &infrastructure);

    EuclidBaseClient *m_base;
};
