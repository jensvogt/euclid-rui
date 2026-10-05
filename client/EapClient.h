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

    // The hosts euclid places applications on - registered by a `euclid-wrk` announcing itself
    // rather than created by anybody, so this is a census of what has turned up and not a list
    // somebody maintains. Not the manager's own host, and not where euclid's modules run: those
    // stay with the manager.
    //
    // Takes nothing. The server answers with the nodes of the caller's account, and the two flags
    // on each are the ones worth reading together: `live` is whether the node has renewed inside
    // the lease period, and `drained` whether it has been taken out of placement while still
    // running what it has. A node can be live and drained at once, which is what draining is for.
    Q_INVOKABLE void fetchNodes();

    // One node by name, for a details page. Answers with the node at the top level rather than
    // under a field, and 404s for a name that is not registered.
    Q_INVOKABLE void fetchNode(const QString &node);

    // Removes a node's *registration*, which is not a way to take a node out of service and must
    // not be offered as one. The leases are left alone and a worker that is still running simply
    // finds itself unregistered on its next renewal and registers again - so deleting a live node
    // achieves nothing except briefly losing its record. Draining it and then stopping the worker
    // is how a node is retired.
    //
    // What it is for: freeing a node name so a different principal can claim it. The first
    // registration of a name binds it, and that binding is what stops one worker inheriting
    // another's instance assignments and application credentials - so giving the name away is a
    // deliberate act, and administrators only, unlike every other node action here.
    Q_INVOKABLE void deleteNode(const QString &node);

    // Takes a node out of placement, or puts it back. Not a stop, and this is the whole point of
    // it: a drained node goes on running what it already has and goes on renewing its leases, and
    // its instances leave only as they are replaced. A node that downed tools on being drained
    // would make draining an outage, which is the opposite of what it is for.
    //
    // By node name, which is what the worker registered as.
    Q_INVOKABLE void setNodeDrained(const QString &node, bool drained);

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

    // Both only write desiredState; the reconciler is what acts on it.
    Q_INVOKABLE void startApplication(const QString &applicationId);
    Q_INVOKABLE void stopApplication(const QString &applicationId);

signals:
    // Each entry: {applicationId, ern, accountId, region, runtime, bucketErn, artifactKey, command,
    // arguments, environment, resources, userId, minInstances, maxInstances, readyTimeoutMs,
    // state, desiredState, instances, created, modified}. `total` is just the number of entries.
    void applicationsLoaded(const QVariantList &applications, int total);
    void applicationsFailed(const QString &message);
    // Each entry: {name, principal, labels, cpuCount, version, os, arch, drained, live, lastSeen}.
    // `os` and `arch` are what the worker's binary was built for, reported on registration; both
    // are empty for a node whose worker predates the fields. `live` is
    // the server's reading against its own lease period rather than something computed from
    // lastSeen here - the client does not know what period the installation runs with, and
    // guessing one would make a node look dead on a deployment that simply renews slowly.
    void nodesLoaded(const QVariantList &nodes, int total);
    void nodesFailed(const QString &message);
    // Confirmed by the server, carrying the state it stored - so a page can say which way it went
    // rather than assuming the click took.
    void nodeDrainChanged(const QString &node, bool drained);
    void nodeDrainFailed(const QString &message);
    // One node, same shape as a nodesLoaded() entry. Carries the name it was asked for, so a page
    // showing one node is not confused by an answer about another.
    void nodeLoaded(const QString &node, const QVariantMap &details);
    void nodeLoadFailed(const QString &node, const QString &message);
    void nodeDeleted(const QString &node);
    void nodeDeleteFailed(const QString &message);
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
    // The bounds as the server stored them, which is both of them even when only one was sent.
    void applicationScaled(const QString &applicationId, int minInstances, int maxInstances);
    // Carries the server's own wording: it is the side that decides what a bound may be, and it
    // names the way out - stopping the application rather than scaling it to nothing.
    void applicationScaleFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
