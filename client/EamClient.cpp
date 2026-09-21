#include "EamClient.h"
#include "EuclidBaseClient.h"

#include <QSet>

EamClient::EamClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}


namespace {

    // The role a namespace grant is written as. "May work in this namespace" was what an
    // accountGrant without isAdmin meant, and `operator` is what says it now: every action except
    // deleting, purging and access management.
    constexpr auto kNamespaceRole = "operator";

    // The role that stands in for what accountGrant.isAdmin used to say.
    constexpr auto kAccountAdminRole = "account-administrator";

    // The grants euclid answers with, folded back into the per-(user, account) shape the pages read.
    // Roles replaced the accountGrants array that used to arrive on each user, and grouping them
    // here keeps that change out of the QML: a page still sees one entry per account with the
    // namespaces in it.
    QHash<QString, QVariantList> grantsByPrincipal(const QJsonArray &grants) {

        struct Folded {
            QSet<QString> namespaces;
            bool isAdmin = false;
            QString granted;
        };
        QHash<QString, QHash<QString, Folded>> byPrincipal;

        for (const auto &value : grants) {
            const QJsonObject grant = value.toObject();
            const QString principal = grant.value("principal").toString();
            const QString accountId = grant.value("accountId").toString();

            Folded &folded = byPrincipal[principal][accountId];
            for (const QJsonArray namespaces = grant.value("namespaces").toArray(); const auto &ns : namespaces)
                folded.namespaces.insert(ns.toString());
            if (grant.value("role").toString() == QLatin1String(kAccountAdminRole))
                folded.isAdmin = true;
            if (folded.granted.isEmpty())
                folded.granted = grant.value("granted").toString();
        }

        QHash<QString, QVariantList> result;
        for (auto principal = byPrincipal.constBegin(); principal != byPrincipal.constEnd(); ++principal) {
            QVariantList entries;
            for (auto account = principal.value().constBegin(); account != principal.value().constEnd(); ++account) {
                QStringList namespaces(account.value().namespaces.constBegin(), account.value().namespaces.constEnd());
                namespaces.sort();

                QVariantMap entry;
                entry["accountId"] = account.key();
                entry["namespaces"] = QVariant(namespaces);
                entry["isAdmin"] = account.value().isAdmin;
                entry["granted"] = account.value().granted;
                entries << entry;
            }
            result.insert(principal.key(), entries);
        }
        return result;
    }

}// namespace

void EamClient::fetchAccounts(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("eam", "list-accounts", body, true,
         [this](const QJsonObject &response) {
             QVariantList accounts;
             for (const QJsonArray array = response.value("accounts").toArray(); const auto &value : array) {
                 const QJsonObject account = value.toObject();
                 QVariantMap entry;
                 entry["accountId"] = account.value("accountId").toString();
                 entry["name"] = account.value("name").toString();
                 entry["ern"] = account.value("ern").toString();
                 entry["description"] = account.value("description").toString();
                 entry["created"] = account.value("created").toString();
                 entry["modified"] = account.value("modified").toString();
                 accounts << entry;
             }
             emit accountsLoaded(accounts, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit accountsFailed(message);
         });
}

void EamClient::createAccount(const QString &accountId, const QString &name, const QString &description) {
    QJsonObject body;
    body["accountId"] = accountId;
    body["name"] = name;
    body["description"] = description;

    m_base->post("eam", "create-account", body, true,
         [this, accountId](const QJsonObject &response) {
             emit accountCreated(accountId);
             emit accountsReload();
         },
         [this](const QString &message) {
             emit accountCreateFailed(message);
         });
}

void EamClient::deleteAccount(const QString &accountId) {
    QJsonObject body;
    body["accountId"] = accountId;

    m_base->post("eam", "delete-account", body, true,
         [this](const QJsonObject &response) {
             emit accountsReload();
         },
         [this](const QString &message) {
             emit accountsFailed(message);
         });
}

void EamClient::fetchNamespaces(const QString &accountId, const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["accountId"] = accountId;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("eam", "list-namespaces", body, true,
         [this](const QJsonObject &response) {
             QVariantList namespaces;
             for (const QJsonArray array = response.value("namespaces").toArray(); const auto &value : array) {
                 const QJsonObject account = value.toObject();
                 QVariantMap entry;
                 entry["accountId"] = account.value("accountId").toString();
                 entry["name"] = account.value("name").toString();
                 entry["ern"] = account.value("ern").toString();
                 entry["description"] = account.value("description").toString();
                 entry["created"] = account.value("created").toString();
                 entry["modified"] = account.value("modified").toString();
                 namespaces << entry;
             }
             emit namespacesLoaded(namespaces, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit namespacesFailed(message);
         });
}

void EamClient::fetchAccountNamespaces(const QString &accountId) {
    QJsonObject body;
    body["accountId"] = accountId;
    body["prefix"] = "";
    body["pageSize"] = 500;
    body["pageIndex"] = 0;
    body["sortColumn"] = "name";
    body["sortDirection"] = "asc";

    m_base->post("eam", "list-namespaces", body, true,
         [this, accountId](const QJsonObject &response) {
             QVariantList namespaces;
             for (const QJsonArray array = response.value("namespaces").toArray(); const auto &value : array) {
                 const QJsonObject entry = value.toObject();
                 QVariantMap mapped;
                 mapped["accountId"] = entry.value("accountId").toString();
                 mapped["name"] = entry.value("name").toString();
                 mapped["ern"] = entry.value("ern").toString();
                 mapped["description"] = entry.value("description").toString();
                 mapped["created"] = entry.value("created").toString();
                 mapped["modified"] = entry.value("modified").toString();
                 namespaces << mapped;
             }
             emit accountNamespacesLoaded(accountId, namespaces);
         },
         [this](const QString &message) {
             emit accountNamespacesFailed(message);
         });
}

void EamClient::fetchAccountUsers(const QString &accountId) {
    QJsonObject body;
    body["prefix"] = "";
    body["pageSize"] = 500;
    body["pageIndex"] = 0;
    body["sortColumn"] = "userId";

    // Two requests, not one per user. Grants used to arrive on each user; they are their own
    // records now, so the list is fetched once for the whole account and joined here - which is why
    // eam list-grants answers for an account when it is given neither a principal nor a role.
    m_base->post("eam", "list-users", body, true,
         [this, accountId](const QJsonObject &userResponse) {

             const QJsonArray array = userResponse.value("users").toArray();

             QJsonObject grantQuery;
             grantQuery["accountId"] = accountId;

             m_base->post("eam", "list-grants", grantQuery, true,
                  [this, accountId, array](const QJsonObject &grantResponse) {

                      const auto grants = grantsByPrincipal(grantResponse.value("grants").toArray());

                      QVariantList users;
                      for (const auto &value : array) {
                          const QJsonObject user = value.toObject();
                          const QString ern = user.value("ern").toString();

                          QVariantList granted;
                          for (const auto &entry : grants.value(ern)) {
                              const QVariantMap grant = entry.toMap();
                              if (grant.value("accountId").toString() != accountId)
                                  continue;
                              granted << grant.value("namespaces").toStringList();
                          }

                          QVariantMap entry;
                          entry["userId"] = user.value("userId").toString();
                          entry["ern"] = ern;
                          entry["email"] = user.value("email").toString();
                          entry["home"] = user.value("accountId").toString() == accountId;
                          entry["namespaces"] = granted;
                          users << entry;
                      }
                      emit accountUsersLoaded(accountId, users);
                  },
                  [this, accountId, array](const QString &) {
                      // The users were read; only the namespaces beside them were not. Emitted
                      // without them rather than discarded: an account-wide grant query is refused
                      // outright by a server that predates it, and losing the whole list of users
                      // over one column is the worse of the two failures.
                      QVariantList users;
                      for (const auto &value : array) {
                          const QJsonObject user = value.toObject();
                          QVariantMap entry;
                          entry["userId"] = user.value("userId").toString();
                          entry["ern"] = user.value("ern").toString();
                          entry["email"] = user.value("email").toString();
                          entry["home"] = user.value("accountId").toString() == accountId;
                          entry["namespaces"] = QVariantList{};
                          users << entry;
                      }
                      emit accountUsersLoaded(accountId, users);
                  });
         },
         [this](const QString &message) {
             emit accountUsersFailed(message);
         });
}

void EamClient::createNamespace(const QString &accountId, const QString &name, const QString &description) {
    QJsonObject body;
    body["accountId"] = accountId;
    body["name"] = name;
    body["description"] = description;

    m_base->post("eam", "create-namespace", body, true,
         [this, name](const QJsonObject &response) {
             emit namespaceCreated(name);
             emit namespacesReload();
         },
         [this](const QString &message) {
             emit namespaceCreateFailed(message);
         });
}

void EamClient::deleteNamespace(const QString &accountId, const QString &name) {
    QJsonObject body;
    body["accountId"] = accountId;
    body["name"] = name;

    m_base->post("eam", "delete-namespace", body, true,
         [this](const QJsonObject &response) {
             emit namespacesReload();
         },
         [this](const QString &message) {
             emit namespacesFailed(message);
         });
}

void EamClient::fetchUsers(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    // One request. The grants used to be fetched alongside and folded into each user as
    // "accountGrants", which nothing reads any more: what a principal may do is shown by the Roles
    // tile on the details page, which asks for that one principal's grants when it is looked at.
    //
    // Worth being deliberate about, because the version that did both broke this list: the users
    // were emitted from inside the *grants* callback, so a listing that had already been read
    // successfully was thrown away whenever the second call failed - and it failed against any
    // server that does not answer an account-wide "list-grants" with neither principal nor role.
    m_base->post("eam", "list-users", body, true,
         [this](const QJsonObject &response) {

             const int total = response.value("total").toInt();

             QVariantList users;
             for (const QJsonArray array = response.value("users").toArray(); const auto &value : array) {
                 const QJsonObject user = value.toObject();

                 QVariantMap entry;
                 // Deliberately not mapping "password" (a hash, but still no reason to ship
                 // it to the UI layer).
                 entry["userId"] = user.value("userId").toString();
                 entry["ern"] = user.value("ern").toString();
                 entry["email"] = user.value("email").toString();
                 entry["accountId"] = user.value("accountId").toString();
                 entry["region"] = user.value("region").toString();
                 entry["created"] = user.value("created").toString();
                 entry["modified"] = user.value("modified").toString();
                 users << entry;
             }
             emit usersLoaded(users, total);
         },
         [this](const QString &message) {
             emit usersFailed(message);
         });
}

void EamClient::createUser(const QString &userId, const QString &password, const QString &email,
                            const QString &accountId, const QString &region, const bool isAdmin) {
    QJsonObject body;
    body["userId"] = userId;
    body["password"] = password;
    body["email"] = email;
    body["accountId"] = accountId;
    body["region"] = region;
    body["isAdmin"] = isAdmin;

    m_base->post("eam", "register", body, true,
         [this, userId](const QJsonObject &response) {
             emit userCreated(userId);
             emit usersReload();
         },
         [this](const QString &message) {
             emit userCreateFailed(message);
         });
}

void EamClient::deleteUser(const QString &userId) {
    QJsonObject body;
    body["userId"] = userId;

    m_base->post("eam", "delete-user", body, true,
         [this](const QJsonObject &response) {
             emit usersReload();
         },
         [this](const QString &message) {
             emit usersFailed(message);
         });
}

void EamClient::changePassword(const QString &userId, const QString &oldPassword, const QString &newPassword) {
    QJsonObject body;
    // Sent even when it is the caller's own, rather than left out: the server reads an absent
    // userId as "mine", which is the same answer, but saying it means the request describes who it
    // is about instead of depending on which session happens to carry it.
    body["userId"] = userId;
    body["oldPassword"] = oldPassword;
    body["newPassword"] = newPassword;

    m_base->post("eam", "change-password", body, true,
         [this, userId](const QJsonObject &) {
             emit passwordChanged(userId);
         },
         [this](const QString &message) {
             emit passwordChangeFailed(message);
         });
}

void EamClient::fetchAccessKeys() {
    m_base->post("eam", "list-access-keys", QJsonObject(), true,
         [this](const QJsonObject &response) {
             QVariantList keys;
             for (const QJsonArray array = response.value("accessKeys").toArray(); const auto &value : array) {
                 const QJsonObject key = value.toObject();
                 QVariantMap entry;
                 entry["accessKeyId"] = key.value("accessKeyId").toString();
                 entry["active"] = key.value("active").toBool();
                 entry["createdAt"] = key.value("createdAt").toString();
                 keys << entry;
             }
             emit accessKeysLoaded(keys);
         },
         [this](const QString &message) {
             emit accessKeysFailed(message);
         });
}

void EamClient::createAccessKey() {
    m_base->post("eam", "create-access-key", QJsonObject(), true,
         [this](const QJsonObject &response) {
             emit accessKeyCreated(response.value("accessKeyId").toString(), response.value("secretAccessKey").toString());
             emit accessKeysReload();
         },
         [this](const QString &message) {
             emit accessKeyCreateFailed(message);
         });
}

void EamClient::deleteAccessKey(const QString &accessKeyId) {
    QJsonObject body;
    body["accessKeyId"] = accessKeyId;

    m_base->post("eam", "delete-access-key", body, true,
         [this, accessKeyId](const QJsonObject &response) {
             emit accessKeyDeleted(accessKeyId);
             emit accessKeysReload();
         },
         [this](const QString &message) {
             emit accessKeysFailed(message);
         });
}

void EamClient::fetchGroupMemberships(const QString &userId) {
    QJsonObject body;
    body["prefix"] = "";
    // One page big enough to hold every group: membership can only be presented as "of all the
    // groups, these ones", so a paged view of it would be meaningless.
    body["pageSize"] = 500;
    body["pageIndex"] = 0;
    body["sortColumn"] = "name";
    body["sortDirection"] = "asc";

    m_base->post("eam", "list-user-groups", body, true,
         [this, userId](const QJsonObject &response) {
             QVariantList groups;
             for (const QJsonArray array = response.value("userGroups").toArray(); const auto &value : array) {
                 const QJsonObject group = value.toObject();
                 QVariantMap entry;
                 entry["name"] = group.value("name").toString();
                 entry["ern"] = group.value("ern").toString();
                 entry["description"] = group.value("description").toString();
                 entry["member"] = group.value("userIds").toArray().contains(QJsonValue(userId));
                 groups << entry;
             }
             emit groupMembershipsLoaded(userId, groups);
         },
         [this](const QString &message) {
             emit groupMembershipsFailed(message);
         });
}

void EamClient::fetchGroupMembers(const QString &groupErn) {
    QJsonObject groupBody;
    groupBody["prefix"] = "";
    groupBody["pageSize"] = 500;
    groupBody["pageIndex"] = 0;
    groupBody["sortColumn"] = "name";
    groupBody["sortDirection"] = "asc";

    // Step one: the group, for its current member list. There is no "get user group" action, so
    // this is the only way to read one back.
    m_base->post("eam", "list-user-groups", groupBody, true,
         [this, groupErn](const QJsonObject &groupResponse) {
             QSet<QString> memberIds;
             for (const QJsonArray groups = groupResponse.value("userGroups").toArray(); const auto &value : groups) {
                 const QJsonObject group = value.toObject();
                 if (group.value("ern").toString() != groupErn)
                     continue;
                 for (const QJsonArray userIds = group.value("userIds").toArray(); const auto &userId : userIds)
                     memberIds.insert(userId.toString());
             }

             QJsonObject userBody;
             userBody["prefix"] = "";
             userBody["pageSize"] = 500;
             userBody["pageIndex"] = 0;
             userBody["sortColumn"] = "userId";

             // Step two: everyone, so the page can offer non-members as well as list members.
             m_base->post("eam", "list-users", userBody, true,
                  [this, groupErn, memberIds](const QJsonObject &userResponse) {
                      QVariantList users;
                      for (const QJsonArray array = userResponse.value("users").toArray(); const auto &value : array) {
                          const QJsonObject user = value.toObject();
                          QVariantMap entry;
                          entry["userId"] = user.value("userId").toString();
                          entry["ern"] = user.value("ern").toString();
                          entry["email"] = user.value("email").toString();
                          entry["member"] = memberIds.contains(user.value("userId").toString());
                          users << entry;
                      }
                      emit groupMembersLoaded(groupErn, users);
                  },
                  [this](const QString &message) { emit groupMembersFailed(message); });
         },
         [this](const QString &message) { emit groupMembersFailed(message); });
}

void EamClient::addUserToGroup(const QString &groupErn, const QString &userErn) {
    QJsonObject body;
    body["userGroup"] = groupErn;
    body["user"] = userErn;

    m_base->post("eam", "user-group-add-user", body, true,
         [this, groupErn, userErn](const QJsonObject &response) {
             emit groupMembershipChanged(groupErn, userErn, true);
         },
         [this](const QString &message) {
             emit groupMembershipFailed(message);
         });
}

void EamClient::removeUserFromGroup(const QString &groupErn, const QString &userErn) {
    QJsonObject body;
    body["userGroup"] = groupErn;
    body["user"] = userErn;

    m_base->post("eam", "user-group-remove-user", body, true,
         [this, groupErn, userErn](const QJsonObject &response) {
             emit groupMembershipChanged(groupErn, userErn, false);
         },
         [this](const QString &message) {
             emit groupMembershipFailed(message);
         });
}

namespace {
// Turns one role - from "list-roles", "get-role", "create-role" or "update-role", which all use
// the same shape - into the map the QML pages read.
QVariantMap roleToMap(const QJsonObject &role) {
    QStringList permissions;
    for (const QJsonArray granted = role.value("permissions").toArray(); const auto &permission: granted)
        permissions << permission.toString();

    QVariantMap entry;
    entry["name"] = role.value("name").toString();
    entry["ern"] = role.value("ern").toString();
    entry["accountId"] = role.value("accountId").toString();
    entry["region"] = role.value("region").toString();
    entry["description"] = role.value("description").toString();
    // The six every installation has. They cannot be changed or deleted, and they are not rows in
    // the account - which is why "created" and "modified" come back empty for them.
    entry["builtin"] = role.value("builtin").toBool();
    entry["permissions"] = permissions;
    // Kept beside the list because that is what a table shows: "128 permissions" says how wide a
    // role is without printing all of them.
    entry["permissionCount"] = permissions.size();
    entry["created"] = role.value("created").toString();
    entry["modified"] = role.value("modified").toString();
    return entry;
}

// Turns one "list-grants" entry into the map the QML pages read.
QVariantMap grantToMap(const QJsonObject &grant) {
    QVariantMap entry;
    entry["grantId"] = grant.value("grantId").toString();
    entry["role"] = grant.value("role").toString();
    entry["principal"] = grant.value("principal").toString();
    entry["accountId"] = grant.value("accountId").toString();
    QStringList namespaces;
    for (const QJsonArray array = grant.value("namespaces").toArray(); const auto &value: array)
        namespaces << value.toString();
    entry["namespaces"] = namespaces;
    QStringList resources;
    for (const QJsonArray array = grant.value("resources").toArray(); const auto &value: array)
        resources << value.toString();
    entry["resources"] = resources;
    entry["granted"] = grant.value("granted").toString();
    // Who wrote it. "euclid" for the one the installation grants itself at bootstrap.
    entry["grantedBy"] = grant.value("grantedBy").toString();
    return entry;
}
}// namespace

void EamClient::fetchRoles(const QString &accountId) {
    QJsonObject body;
    // Omitted rather than sent empty: absent means the caller's own account, and naming another is
    // something only an administrator of it may do.
    if (!accountId.isEmpty())
        body["accountId"] = accountId;

    // Every field spelled out, and this one above all. Dto::EAM::ListRolesRequest declares
    // includeBuiltin as true, but its JSON reader assigns GetBoolValue() unconditionally - which
    // answers false for a key that is not there - so leaving it out asks for the opposite of the
    // documented default and the six built-in roles simply do not come back. The same goes for
    // sortColumn and sortDirection, which arrive empty rather than as "name" and "asc".
    body["includeBuiltin"] = true;
    body["prefix"] = "";
    // The built-ins are outside the paging and the account's own roles are few; one page of them is
    // what this list is. The request's own default is ten, which would quietly cut the eleventh.
    body["pageSize"] = 500;
    body["pageIndex"] = 0;
    body["sortColumn"] = "name";
    body["sortDirection"] = "asc";

    m_base->post("eam", "list-roles", body, true,
         [this](const QJsonObject &response) {
             QVariantList roles;
             for (const QJsonArray array = response.value("roles").toArray(); const auto &value: array)
                 roles << roleToMap(value.toObject());
             emit rolesLoaded(roles);
         },
         [this](const QString &message) {
             emit rolesFailed(message);
         });
}

void EamClient::fetchRole(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("eam", "get-role", body, true,
         [this, name](const QJsonObject &response) {
             emit roleLoaded(name, roleToMap(response.value("role").toObject()));
         },
         [this, name](const QString &message) {
             emit roleLoadFailed(name, message);
         });
}

void EamClient::fetchPermissions() {
    m_base->post("eam", "list-permissions", QJsonObject{}, true,
         [this](const QJsonObject &response) {
             QStringList permissions;
             for (const QJsonArray array = response.value("permissions").toArray(); const auto &value: array)
                 permissions << value.toString();
             QStringList modules;
             for (const QJsonArray array = response.value("modules").toArray(); const auto &value: array)
                 modules << value.toString();
             QStringList unbindable;
             for (const QJsonArray array = response.value("unbindableModules").toArray(); const auto &value: array)
                 unbindable << value.toString();
             emit permissionsLoaded(permissions, modules, unbindable);
         },
         [this](const QString &message) {
             emit permissionsFailed(message);
         });
}

void EamClient::createRole(const QString &name, const QStringList &permissions, const QString &description) {
    QJsonObject body;
    body["name"] = name;
    body["permissions"] = QJsonArray::fromStringList(permissions);
    body["description"] = description;

    m_base->post("eam", "create-role", body, true,
         [this, name](const QJsonObject &response) {
             emit roleCreated(name, roleToMap(response.value("role").toObject()));
             emit rolesReload();
         },
         [this](const QString &message) {
             emit roleCreateFailed(message);
         });
}

void EamClient::updateRole(const QString &name, const QStringList &permissions, const QString &description) {
    QJsonObject body;
    body["name"] = name;
    // Sent whole, because the server replaces rather than merges: what is left out is taken away,
    // which is the only way to narrow a role.
    body["permissions"] = QJsonArray::fromStringList(permissions);
    body["description"] = description;

    m_base->post("eam", "update-role", body, true,
         [this, name](const QJsonObject &response) {
             emit roleUpdated(name, roleToMap(response.value("role").toObject()));
             emit rolesReload();
         },
         [this](const QString &message) {
             emit roleUpdateFailed(message);
         });
}

void EamClient::deleteRole(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("eam", "delete-role", body, true,
         [this, name](const QJsonObject &) {
             emit roleDeleted(name);
             emit rolesReload();
         },
         [this](const QString &message) {
             emit roleDeleteFailed(message);
         });
}

void EamClient::fetchRoleGrants(const QString &role, const QString &accountId) {
    QJsonObject body;
    body["role"] = role;
    if (!accountId.isEmpty())
        body["accountId"] = accountId;

    m_base->post("eam", "list-grants", body, true,
         [this, role](const QJsonObject &response) {
             QVariantList grants;
             for (const QJsonArray array = response.value("grants").toArray(); const auto &value: array)
                 grants << grantToMap(value.toObject());
             emit roleGrantsLoaded(role, grants);
         },
         [this, role](const QString &message) {
             emit roleGrantsFailed(role, message);
         });
}

void EamClient::fetchGrants(const QString &principalErn) {
    QJsonObject body;
    body["principal"] = principalErn;

    m_base->post("eam", "list-grants", body, true,
         [this, principalErn](const QJsonObject &response) {
             QVariantList grants;
             for (const QJsonArray array = response.value("grants").toArray(); const auto &value: array)
                 grants << grantToMap(value.toObject());
             emit grantsLoaded(principalErn, grants);
         },
         [this, principalErn](const QString &message) {
             emit grantsFailed(principalErn, message);
         });
}

void EamClient::grantRole(const QString &role, const QString &principalErn, const QStringList &namespaces,
                          const QStringList &resources, const QString &accountId) {
    QJsonObject body;
    body["role"] = role;
    body["principal"] = principalErn;
    body["namespaces"] = QJsonArray::fromStringList(namespaces);
    body["resources"] = QJsonArray::fromStringList(resources);
    if (!accountId.isEmpty())
        body["accountId"] = accountId;

    m_base->post("eam", "grant-role", body, true,
         [this, principalErn](const QJsonObject &response) {
             emit roleGranted(principalErn, response.value("grantId").toString());
         },
         [this](const QString &message) {
             emit roleGrantFailed(message);
         });
}

void EamClient::revokeRole(const QString &grantId, const QString &principalErn) {
    QJsonObject body;
    body["grantId"] = grantId;

    m_base->post("eam", "revoke-role", body, true,
         [this, principalErn, grantId](const QJsonObject &) {
             emit roleRevoked(principalErn, grantId);
         },
         [this](const QString &message) {
             emit roleRevokeFailed(message);
         });
}

void EamClient::grantNamespaceAccess(const QString &userErn, const QString &accountId, const QString &namespaceName) {

    // "grant-namespace-access" is gone: access to a namespace is a role granted in it. The role is
    // `operator`, which is what an accountGrant without isAdmin allowed - everything except
    // deleting, purging and access management.
    QJsonObject body;
    body["role"] = QString::fromLatin1(kNamespaceRole);
    body["principal"] = userErn;
    body["accountId"] = accountId;
    body["namespaces"] = QJsonArray{namespaceName};
    body["resources"] = QJsonArray{QStringLiteral("*")};

    m_base->post("eam", "grant-role", body, true,
         [this, userErn, accountId, namespaceName](const QJsonObject &) {
             emit namespaceAccessChanged(userErn, accountId, namespaceName, true);
         },
         [this](const QString &message) {
             emit namespaceAccessFailed(message);
         });
}

void EamClient::revokeNamespaceAccess(const QString &userErn, const QString &accountId, const QString &namespaceName) {

    // Two round trips, because a grant is revoked by its own id and the caller only knows which
    // namespace it wants back. So: read this principal's grants, find the ones naming that
    // namespace, and revoke them.
    QJsonObject query;
    query["principal"] = userErn;

    m_base->post("eam", "list-grants", query, true,
         [this, userErn, accountId, namespaceName](const QJsonObject &response) {

             QStringList revoke;
             QJsonObject narrow;

             for (const QJsonArray grants = response.value("grants").toArray(); const auto &value : grants) {
                 const QJsonObject grant = value.toObject();
                 if (grant.value("accountId").toString() != accountId)
                     continue;

                 QStringList namespaces;
                 for (const QJsonArray array = grant.value("namespaces").toArray(); const auto &ns : array)
                     namespaces << ns.toString();
                 if (!namespaces.contains(namespaceName))
                     continue;

                 revoke << grant.value("grantId").toString();

                 // A grant that named other namespaces too has to come back without this one: a
                 // grant's scope is fixed once written, so narrowing it means revoking it and
                 // writing what is left.
                 if (namespaces.removeAll(namespaceName), !namespaces.isEmpty()) {
                     narrow = grant;
                     narrow["namespaces"] = QJsonArray::fromStringList(namespaces);
                 }
             }

             if (revoke.isEmpty()) {
                 emit namespaceAccessFailed(tr("No grant for namespace '%1' to revoke").arg(namespaceName));
                 return;
             }

             for (const auto &grantId : revoke) {
                 QJsonObject body;
                 body["grantId"] = grantId;
                 m_base->post("eam", "revoke-role", body, true,
                      [this, userErn, accountId, namespaceName, narrow](const QJsonObject &) {
                          if (!narrow.isEmpty()) {
                              QJsonObject regrant;
                              regrant["role"] = narrow.value("role");
                              regrant["principal"] = narrow.value("principal");
                              regrant["accountId"] = narrow.value("accountId");
                              regrant["namespaces"] = narrow.value("namespaces");
                              regrant["resources"] = narrow.value("resources");
                              m_base->post("eam", "grant-role", regrant, true,
                                   [](const QJsonObject &) {},
                                   [this](const QString &message) { emit namespaceAccessFailed(message); });
                          }
                          emit namespaceAccessChanged(userErn, accountId, namespaceName, false);
                      },
                      [this](const QString &message) {
                          emit namespaceAccessFailed(message);
                      });
             }
         },
         [this](const QString &message) {
             emit namespaceAccessFailed(message);
         });
}

void EamClient::fetchUserGroups(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("eam", "list-user-groups", body, true,
         [this](const QJsonObject &response) {
             QVariantList groups;
             for (const QJsonArray array = response.value("userGroups").toArray(); const auto &value : array) {
                 const QJsonObject group = value.toObject();
                 QVariantMap entry;
                 entry["name"] = group.value("name").toString();
                 entry["ern"] = group.value("ern").toString();
                 entry["accountId"] = group.value("accountId").toString();
                 entry["region"] = group.value("region").toString();
                 entry["description"] = group.value("description").toString();
                 entry["userIds"] = group.value("userIds").toArray().toVariantList();
                 entry["created"] = group.value("created").toString();
                 entry["modified"] = group.value("modified").toString();
                 groups << entry;
             }
             emit userGroupsLoaded(groups, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit userGroupsFailed(message);
         });
}

void EamClient::createUserGroup(const QString &name, const QString &description) {
    QJsonObject body;
    body["name"] = name;
    body["description"] = description;

    m_base->post("eam", "create-user-group", body, true,
         [this, name](const QJsonObject &response) {
             emit userGroupCreated(name);
             emit userGroupsReload();
         },
         [this](const QString &message) {
             emit userGroupCreateFailed(message);
         });
}

void EamClient::deleteUserGroup(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("eam", "delete-user-group", body, true,
         [this](const QJsonObject &response) {
             emit userGroupsReload();
         },
         [this](const QString &message) {
             emit userGroupsFailed(message);
         });
}
