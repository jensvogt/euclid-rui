#include "EamClient.h"
#include "EuclidBaseClient.h"

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

void EamClient::fetchUsers(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;

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
