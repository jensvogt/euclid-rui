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
    Q_PROPERTY(QString accountId READ accountId NOTIFY accountIdChanged)
    Q_PROPERTY(QString region READ region NOTIFY regionChanged)
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)

public:
    explicit EuclidBaseClient(QObject *parent = nullptr);

    [[nodiscard]]
    bool busy() const { return m_busy; }

    // The euclid-mgr gateway every request is posted to, e.g. "https://localhost:5566/". Owned by
    // AppSettings (which persists it and composes it from host/port/scheme) and pushed in from
    // main.cpp, so this class stays free of any settings dependency.
    [[nodiscard]]
    QString baseUrl() const { return m_baseUrl; }

    // Pointing at a different gateway invalidates the session: a token minted by one euclid-mgr
    // means nothing to another, and the account/region/namespace it resolved belong to that
    // backend too. So this drops all of it and reports the session as ended, rather than letting
    // the next request fail in a way that looks like a server error.
    Q_INVOKABLE void setBaseUrl(const QString &baseUrl);

    // How authorized requests prove who they are: "bearer" sends the JWT the password login
    // returned, "sigv4" and "rfc9421" sign every request with an EAM access key instead. Pushed
    // in from main.cpp out of AppSettings, same as the base URL. A signature mode with no key
    // configured falls back to the bearer token rather than sending an unauthenticated request.
    Q_INVOKABLE void setAuthMode(const QString &authMode);
    Q_INVOKABLE void setAccessKey(const QString &accessKeyId, const QString &secretAccessKey);

    // Empty until login() succeeds.
    [[nodiscard]]
    QString accountId() const { return m_accountId; }

    // Empty until login() succeeds.
    [[nodiscard]]
    QString region() const { return m_region; }

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
    void accountIdChanged();
    void regionChanged();
    void baseUrlChanged();
    // The session was dropped without the user signing out - currently only because the gateway
    // address changed under it (see setBaseUrl()).
    void sessionCleared();
    void loginSucceeded();
    void loginFailed(const QString &message);
    void namespacesLoaded(const QStringList &namespaces);
    void namespacesFailed(const QString &message);

private:
    void setBusy(bool busy);

    // Applies whichever scheme m_authMode names to a request that is about to be sent. `target`
    // and `action` are already on the request; the body is passed separately because the
    // signature covers it and QNetworkRequest cannot be asked for it afterwards.
    void authorize(QNetworkRequest &request, const QByteArray &body);

    QNetworkAccessManager m_networkManager;
    QString m_baseUrl;
    QString m_authMode{QStringLiteral("bearer")};
    QString m_accessKeyId;
    QString m_secretAccessKey;
    QString m_token;
    QString m_userId;
    QString m_accountId;
    QString m_region;
    QString m_namespace;
    bool m_busy = false;
};
