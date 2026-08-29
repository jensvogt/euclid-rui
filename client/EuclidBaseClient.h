#pragma once

#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <functional>

// Shared HTTP/session foundation: owns the network manager and the current
// login session (token/account/region/namespace), and exposes the EAM
// (account/auth) calls. Module-specific clients (EqsClient, EsmClient, ...)
// hold a pointer to a single shared instance of this and issue requests
// through it, so every client rides the same authenticated session.
class EuclidBaseClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit EuclidBaseClient(QObject *parent = nullptr);

    [[nodiscard]]
    bool busy() const { return m_busy; }

    Q_INVOKABLE void login(const QString &userId, const QString &password);
    Q_INVOKABLE void fetchNamespaces();
    Q_INVOKABLE void setNamespace(const QString &namespaceName);

    // POSTs a euclid gateway request (header-routed via x-euclid-target/
    // x-euclid-action). Public so module client classes can issue requests
    // through this shared session instead of duplicating auth/session state.
    void post(const QString &target, const QString &action, const QJsonObject &body, bool authorized,
              const std::function<void(const QJsonObject &)> &onSuccess,
              const std::function<void(const QString &)> &onError);

    // Like post(), but sends a raw binary body (e.g. file contents) with extra raw headers, instead
    // of a JSON body. Always authorized - every raw-upload action needs a session. Used for actions
    // like ESM's "put-object" that read the request body as bytes rather than JSON.
    void postRaw(const QString &target, const QString &action, const QVariantMap &extraHeaders, const QByteArray &body,
                 const std::function<void(const QJsonObject &)> &onSuccess,
                 const std::function<void(const QString &)> &onError);

signals:
    void busyChanged();
    void loginSucceeded();
    void loginFailed(const QString &message);
    void namespacesLoaded(const QStringList &namespaces);
    void namespacesFailed(const QString &message);

private:
    void setBusy(bool busy);

    QNetworkAccessManager m_networkManager;
    QString m_token;
    QString m_accountId;
    QString m_region;
    QString m_namespace;
    bool m_busy = false;
};
