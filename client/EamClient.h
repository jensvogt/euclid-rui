#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QJsonArray>
#include <QJsonObject>

class EuclidBaseClient;

// EAM (key management service) calls.
class EamClient : public QObject {
    Q_OBJECT

public:
    explicit EamClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    Q_INVOKABLE void fetchAccounts(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("name"), const QString &sortDirection = QStringLiteral("asc"));
    // Global-admin only server-side.
    Q_INVOKABLE void createAccount(const QString &accountId, const QString &name, const QString &description = QString());
    // Global-admin only; fails (409) if the account still has namespaces or user grants.
    Q_INVOKABLE void deleteAccount(const QString &accountId);

    Q_INVOKABLE void fetchNamespaces(const QString &accountId, const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("name"), const QString &sortDirection = QStringLiteral("asc"));

    // Every namespace of one account, unpaged, for the account details page. Separate from
    // fetchNamespaces()/namespacesLoaded() so a details page doesn't replace what the paged
    // namespaces table is showing.
    Q_INVOKABLE void fetchAccountNamespaces(const QString &accountId);

    // Every user in the deployment, each annotated with how they relate to accountId: `home` if
    // it is their registered account, and `namespaces` listing the ones they hold an explicit
    // grant for there (empty for most users). Serves both the account details page ("who can
    // reach this account") and the namespace details page, which reads `namespaces` to decide
    // whether a given user is granted the namespace it is showing.
    Q_INVOKABLE void fetchAccountUsers(const QString &accountId);
    // Requires account-admin (global admin or a per-account grant) on accountId.
    Q_INVOKABLE void createNamespace(const QString &accountId, const QString &name, const QString &description = QString());
    // Requires account-admin; fails (409) if any user still has a grant naming this namespace.
    Q_INVOKABLE void deleteNamespace(const QString &accountId, const QString &name);

    // ListUserRequest has no sortDirection field server-side, unlike the other list actions here.
    Q_INVOKABLE void fetchUsers(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("userId"));
    // Wire action is "register", not "create-user" - registering a user IS how one gets created.
    // Admin-only server-side (except the very first user ever registered).
    Q_INVOKABLE void createUser(const QString &userId, const QString &password, const QString &email,
                                 const QString &accountId, const QString &region, bool isAdmin = false);
    // Admin-only; deletes unconditionally (no check for group membership).
    Q_INVOKABLE void deleteUser(const QString &userId);

    // Every user group in the deployment, each flagged with whether userId is currently a member -
    // which is how one user's memberships are read, there being no "list groups of user" action
    // server-side (membership lives on the group, in UserGroup.userIds).
    //
    // Deliberately not reusing fetchUsers()/fetchUserGroups() and their signals: those drive the
    // paged tables on the users and user-groups pages, and a details page borrowing them would
    // replace what those tables are showing.
    Q_INVOKABLE void fetchGroupMemberships(const QString &userId);

    // Access keys of the *signed-in user*, always - "create-access-key"/"list-access-keys"/
    // "delete-access-key" act on whoever the request authenticates as (see EamServer's handlers),
    // so there is no admin view of somebody else's keys to build here.
    Q_INVOKABLE void fetchAccessKeys();
    // The secret comes back exactly once, in this response; the list action never returns it
    // again. Whoever handles accessKeyCreated() has to keep it or lose it.
    Q_INVOKABLE void createAccessKey();
    Q_INVOKABLE void deleteAccessKey(const QString &accessKeyId);

    // The mirror image, for a group details page: every user in the deployment, each flagged with
    // whether they are in the group named by groupErn. Costs two round trips - the group record
    // carries the membership (UserGroup.userIds) and the user records carry the ERNs that
    // addUserToGroup()/removeUserFromGroup() need - and re-reads the group rather than trusting a
    // caller-supplied member list, so it stays correct after a membership change.
    Q_INVOKABLE void fetchGroupMembers(const QString &groupErn);

    // Both take ERNs, not names - "user-group-add-user"/"user-group-remove-user" resolve their
    // arguments by ERN server-side. Admin-only.
    Q_INVOKABLE void addUserToGroup(const QString &groupErn, const QString &userErn);
    Q_INVOKABLE void removeUserFromGroup(const QString &groupErn, const QString &userErn);

    // Grants/revokes one user's access to one namespace of one account, on top of their home
    // account. Requires account-admin on accountId (not necessarily global admin). userErn is an
    // ERN; the namespace must already exist.
    Q_INVOKABLE void grantNamespaceAccess(const QString &userErn, const QString &accountId, const QString &namespaceName);
    Q_INVOKABLE void revokeNamespaceAccess(const QString &userErn, const QString &accountId, const QString &namespaceName);

    Q_INVOKABLE void fetchUserGroups(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("userId"), const QString &sortDirection = QStringLiteral("asc"));
    // Admin-only; group name must be unique across the deployment. Starts empty - members are
    // added afterward via user-group-add-user (not yet exposed here).
    Q_INVOKABLE void createUserGroup(const QString &name, const QString &description = QString());
    // Admin-only; no check for remaining members.
    Q_INVOKABLE void deleteUserGroup(const QString &name);

signals:
    void accountsLoaded(const QVariantList &keys, int total);
    void accountsFailed(const QString &message);
    void accountsReload();
    void accountCreated(const QString &accountId);
    void accountCreateFailed(const QString &message);

    // Each entry: {accountId, name, ern, description, created, modified}.
    void accountNamespacesLoaded(const QString &accountId, const QVariantList &namespaces);
    void accountNamespacesFailed(const QString &message);
    // Each entry: {userId, ern, email, home: bool, namespaces: [string]}.
    void accountUsersLoaded(const QString &accountId, const QVariantList &users);
    void accountUsersFailed(const QString &message);

    void namespacesLoaded(const QVariantList &keys, int total);
    void namespacesFailed(const QString &message);
    void namespacesReload();
    void namespaceCreated(const QString &name);
    void namespaceCreateFailed(const QString &message);

    void usersLoaded(const QVariantList &users, int total);
    void usersFailed(const QString &message);
    void usersReload();
    void userCreated(const QString &userId);
    void userCreateFailed(const QString &message);

    // Each entry: {accessKeyId, active, createdAt}. Never a secret.
    void accessKeysLoaded(const QVariantList &accessKeys);
    void accessKeysFailed(const QString &message);
    void accessKeyCreated(const QString &accessKeyId, const QString &secretAccessKey);
    void accessKeyCreateFailed(const QString &message);
    void accessKeyDeleted(const QString &accessKeyId);
    void accessKeysReload();

    // Each entry: {name, ern, description, member: bool}. userId echoes the request, so a details
    // page can ignore a response for someone else.
    void groupMembershipsLoaded(const QString &userId, const QVariantList &groups);
    void groupMembershipsFailed(const QString &message);
    // Each entry: {userId, ern, email, member: bool}. groupErn echoes the request.
    void groupMembersLoaded(const QString &groupErn, const QVariantList &users);
    void groupMembersFailed(const QString &message);
    // Emitted once the server has confirmed the change; `member` says which way it went.
    void groupMembershipChanged(const QString &groupErn, const QString &userErn, bool member);
    void groupMembershipFailed(const QString &message);

    // Likewise for namespace grants: `granted` false means the grant was revoked.
    void namespaceAccessChanged(const QString &userErn, const QString &accountId, const QString &namespaceName, bool granted);
    void namespaceAccessFailed(const QString &message);

    void userGroupsLoaded(const QVariantList &groups, int total);
    void userGroupsFailed(const QString &message);
    void userGroupsReload();
    void userGroupCreated(const QString &name);
    void userGroupCreateFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
