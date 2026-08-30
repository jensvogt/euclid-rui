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
    // Requires account-admin (global admin or a per-account grant) on accountId.
    Q_INVOKABLE void createNamespace(const QString &accountId, const QString &name, const QString &description = QString());
    // Requires account-admin; fails (409) if any user still has a grant naming this namespace.
    Q_INVOKABLE void deleteNamespace(const QString &accountId, const QString &name);

    // ListUserRequest has no sortDirection field server-side, unlike the other list actions here.
    Q_INVOKABLE void fetchUsers(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("userId"));
    Q_INVOKABLE void fetchUserGroups(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10, const QString &sortColumn = QStringLiteral("userId"), const QString &sortDirection = QStringLiteral("asc"));

signals:
    void accountsLoaded(const QVariantList &keys, int total);
    void accountsFailed(const QString &message);
    void accountsReload();
    void accountCreated(const QString &accountId);
    void accountCreateFailed(const QString &message);

    void namespacesLoaded(const QVariantList &keys, int total);
    void namespacesFailed(const QString &message);
    void namespacesReload();
    void namespaceCreated(const QString &name);
    void namespaceCreateFailed(const QString &message);

    void usersLoaded(const QVariantList &users, int total);
    void usersFailed(const QString &message);
    void userGroupsLoaded(const QVariantList &groups, int total);
    void userGroupsFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
