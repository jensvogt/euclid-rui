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
    Q_INVOKABLE void fetchUsers(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("userId"), const QString &sortDirection = QStringLiteral("asc"));
    // Wire action is "register", not "create-user" - registering a user IS how one gets created.
    // Admin-only server-side (except the very first user ever registered).
    Q_INVOKABLE void createUser(const QString &userId, const QString &password, const QString &email,
                                 const QString &accountId, const QString &region, bool isAdmin = false);
    // Admin-only; deletes unconditionally (no check for group membership).
    Q_INVOKABLE void deleteUser(const QString &userId);

    // Replaces a password. Which of the two things this is - somebody changing their own, or an
    // administrator resetting somebody else's - is decided server-side by the userId alone and not
    // by what the request carries, so a caller cannot reach the reset path just by omitting the old
    // password. Naming yourself is the same request as leaving userId empty: both are the
    // own-password path, and both need oldPassword. Naming anybody else is the reset, where
    // oldPassword is ignored and being an administrator is the proof.
    //
    // Three refusals worth telling apart in the UI, because only the first is a mistake the user
    // can correct in the dialog: the old password not matching (403), not being an administrator
    // (403), and a user who has no password to change at all (409) - a federated login or an
    // application's technical principal, which were deliberately created without one. See
    // EamServer::handleChangePassword.
    //
    // Note what it does not do: a session already holding a token keeps it, here and everywhere
    // else. The token is a JWT checked against the signing secret rather than against anything
    // stored, so changing a password closes the door on the next login, not on the current session.
    Q_INVOKABLE void changePassword(const QString &userId, const QString &oldPassword, const QString &newPassword);

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

    // ── Roles and grants ─────────────────────────────────────────────────────
    // What authorization is actually made of: a role is a named set of permissions, and a grant
    // gives one to a principal - a user or a user group - in named namespaces and over named
    // resources. The pair above is the narrow case of this, fixed to the "operator" role.

    // Every role the account can grant: the six built-ins and whatever has been created alongside
    // them. Asked for by the grant dialog, which offers them rather than taking a typed name that
    // the server would then refuse.
    Q_INVOKABLE void fetchRoles(const QString &accountId = QString());

    // One role and every permission it holds. Answers for a built-in too, which is the only way to
    // see what one of those actually covers - they are not rows in the account.
    Q_INVOKABLE void fetchRole(const QString &name);

    // Every permission a role may hold, with the modules they belong to. "unbindable" names the
    // modules no role can reach (emm and emd): they gate themselves, so no permission of theirs
    // exists to be granted.
    Q_INVOKABLE void fetchPermissions();

    // A role needs at least one permission - one that grants nothing is a mistake rather than a
    // starting point - and every one is checked against what the modules actually dispatch.
    Q_INVOKABLE void createRole(const QString &name, const QStringList &permissions, const QString &description = QString());

    // Replaces rather than merges: a permission left out is taken away, which is the only way to
    // narrow a role. Built-in roles are refused.
    Q_INVOKABLE void updateRole(const QString &name, const QStringList &permissions, const QString &description = QString());

    // Refused while anything still holds it - revoke those grants first - and refused outright for
    // a built-in.
    Q_INVOKABLE void deleteRole(const QString &name);

    // Who holds a role, which is the other half of "what may they do". Its own signal so a page
    // showing a role's holders is not confused by a principal's grant list.
    Q_INVOKABLE void fetchRoleGrants(const QString &role, const QString &accountId = QString());

    // One principal's grants. Takes a user ERN or a user-group ERN - the ERN is what says which,
    // and the server resolves it either way.
    Q_INVOKABLE void fetchGrants(const QString &principalErn);

    // Namespaces and resources are both required by the server and both take "*". A grant that
    // applies in no namespace grants nothing, which is a mistake rather than a configuration, so
    // there is no "leave it empty" here either.
    Q_INVOKABLE void grantRole(const QString &role, const QString &principalErn,
                               const QStringList &namespaces, const QStringList &resources,
                               const QString &accountId = QString());

    // By grant id, which is what list-grants answers with: a grant's scope is fixed once written,
    // so narrowing one means revoking it and writing what is left.
    Q_INVOKABLE void revokeRole(const QString &grantId, const QString &principalErn);

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
    // Carries the userId back so a dialog can tell its own result from one belonging to another
    // open on the same client - these signals reach every listener, not just the caller.
    void passwordChanged(const QString &userId);
    void passwordChangeFailed(const QString &message);

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

    // Each role: {name, description, builtin, permissions, permissionCount}. "builtin" marks the
    // six every installation has, which cannot be redefined or deleted.
    void rolesLoaded(const QVariantList &roles);
    void rolesFailed(const QString &message);
    void rolesReload();
    void roleLoaded(const QString &name, const QVariantMap &role);
    void roleLoadFailed(const QString &name, const QString &message);
    // {permissions, modules, unbindableModules}
    void permissionsLoaded(const QStringList &permissions, const QStringList &modules, const QStringList &unbindableModules);
    void permissionsFailed(const QString &message);
    void roleCreated(const QString &name, const QVariantMap &role);
    void roleCreateFailed(const QString &message);
    void roleUpdated(const QString &name, const QVariantMap &role);
    void roleUpdateFailed(const QString &message);
    void roleDeleted(const QString &name);
    void roleDeleteFailed(const QString &message);
    // The grants that name one role, rather than one principal.
    void roleGrantsLoaded(const QString &role, const QVariantList &grants);
    void roleGrantsFailed(const QString &role, const QString &message);
    // Each grant: {grantId, role, principal, accountId, namespaces, resources, granted, grantedBy}.
    // Carries the principal it was asked for, so a page showing one is not confused by an answer
    // about another.
    void grantsLoaded(const QString &principalErn, const QVariantList &grants);
    void grantsFailed(const QString &principalErn, const QString &message);
    void roleGranted(const QString &principalErn, const QString &grantId);
    void roleGrantFailed(const QString &message);
    void roleRevoked(const QString &principalErn, const QString &grantId);
    void roleRevokeFailed(const QString &message);

    void userGroupsLoaded(const QVariantList &groups, int total);
    void userGroupsFailed(const QString &message);
    void userGroupsReload();
    void userGroupCreated(const QString &name);
    void userGroupCreateFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
