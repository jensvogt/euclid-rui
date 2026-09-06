#include "EamClient.h"
#include "EuclidBaseClient.h"

#include <QSet>

EamClient::EamClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

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

    m_base->post("eam", "list-users", body, true,
         [this, accountId](const QJsonObject &response) {
             QVariantList users;
             for (const QJsonArray array = response.value("users").toArray(); const auto &value : array) {
                 const QJsonObject user = value.toObject();

                 // Grants are stored on the user, one entry per account, so this is where an
                 // account's or namespace's access list has to be assembled from.
                 QVariantList granted;
                 for (const QJsonArray grants = user.value("accountGrants").toArray(); const auto &grantValue : grants) {
                     const QJsonObject grant = grantValue.toObject();
                     if (grant.value("accountId").toString() != accountId)
                         continue;
                     for (const QJsonArray namespaces = grant.value("namespaces").toArray(); const auto &ns : namespaces)
                         granted << ns.toString();
                 }

                 QVariantMap entry;
                 entry["userId"] = user.value("userId").toString();
                 entry["ern"] = user.value("ern").toString();
                 entry["email"] = user.value("email").toString();
                 entry["home"] = user.value("accountId").toString() == accountId;
                 entry["namespaces"] = granted;
                 users << entry;
             }
             emit accountUsersLoaded(accountId, users);
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

    m_base->post("eam", "list-users", body, true,
         [this](const QJsonObject &response) {
             QVariantList users;
             for (const QJsonArray array = response.value("users").toArray(); const auto &value : array) {
                 const QJsonObject user = value.toObject();
                 QVariantMap entry;
                 // Deliberately not mapping "password" (a hash, but still no reason to ship it to
                 // the UI layer).
                 entry["userId"] = user.value("userId").toString();
                 entry["ern"] = user.value("ern").toString();
                 entry["email"] = user.value("email").toString();
                 entry["accountId"] = user.value("accountId").toString();
                 entry["region"] = user.value("region").toString();
                 entry["created"] = user.value("created").toString();
                 entry["modified"] = user.value("modified").toString();
                 // Explicit per-(account, namespace) grants on top of the user's home account -
                 // the user details page reads and edits these.
                 QVariantList grants;
                 for (const QJsonArray grantArray = user.value("accountGrants").toArray(); const auto &grantValue : grantArray) {
                     const QJsonObject grant = grantValue.toObject();
                     QVariantMap grantEntry;
                     grantEntry["accountId"] = grant.value("accountId").toString();
                     grantEntry["namespaces"] = grant.value("namespaces").toArray().toVariantList();
                     grantEntry["isAdmin"] = grant.value("isAdmin").toBool();
                     grantEntry["granted"] = grant.value("granted").toString();
                     grants << grantEntry;
                 }
                 entry["accountGrants"] = grants;
                 users << entry;
             }
             emit usersLoaded(users, response.value("total").toInt());
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

void EamClient::grantNamespaceAccess(const QString &userErn, const QString &accountId, const QString &namespaceName) {
    QJsonObject body;
    body["user"] = userErn;
    body["accountId"] = accountId;
    body["namespace"] = namespaceName;

    m_base->post("eam", "grant-namespace-access", body, true,
         [this, userErn, accountId, namespaceName](const QJsonObject &response) {
             emit namespaceAccessChanged(userErn, accountId, namespaceName, true);
         },
         [this](const QString &message) {
             emit namespaceAccessFailed(message);
         });
}

void EamClient::revokeNamespaceAccess(const QString &userErn, const QString &accountId, const QString &namespaceName) {
    QJsonObject body;
    body["user"] = userErn;
    body["accountId"] = accountId;
    body["namespace"] = namespaceName;

    m_base->post("eam", "revoke-namespace-access", body, true,
         [this, userErn, accountId, namespaceName](const QJsonObject &response) {
             emit namespaceAccessChanged(userErn, accountId, namespaceName, false);
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
