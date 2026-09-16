#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// EAD (audit) calls: the trail of commands euclid recorded, one entry per command that changed
// something and one per command that was refused or failed.
//
// Two things about the trail shape what can be asked of it here. It is confined to the caller's
// own account server-side, whatever the request says - EAD is the one module built to be read by
// somebody looking for the shape of an installation, so letting an account read another's would
// hand over exactly that. And it is not confined to the caller's own *user*: narrowing to one is
// this client's job, by naming them, which is what lets an administrator see everybody's while
// everybody else sees their own.
class EadClient : public QObject {
    Q_OBJECT

public:
    explicit EadClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // The most recent commands first. Every filter is optional and an empty one is not applied, so
    // no arguments at all means "everything this account did".
    //
    // `userId` matches what the caller sent in its x-euclid-user-id header at the time, which is
    // what EAD stored - not a resolved account name. For the RUI that is euclidClient.userId.
    Q_INVOKABLE void fetchEvents(const QString &userId = QString(), const QString &moduleName = QString(),
                                 const QString &command = QString(), int pageIndex = 0, int pageSize = 10);

signals:
    // The page of events and the total the filter matches, which is what paging needs and is not
    // the same as the number of entries handed over.
    void eventsLoaded(const QVariantList &events, int total);
    void eventsFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
