#include "EuclidBaseClient.h"
#include "RequestSigner.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QUrl>

namespace {
// Only the starting value: main.cpp overwrites it with the persisted AppSettings::baseUrl() before
// the first request, and the login dialog can point it somewhere else at any time.
constexpr auto kDefaultBaseUrl = "https://localhost:5566/";
// The gateway (and/or intermediate infra) can silently close an idle keep-alive connection;
// QNetworkAccessManager doesn't always notice before trying to reuse it, which otherwise leaves
// the request hanging forever with no error and no timeout. Bound every request so a stale
// connection surfaces as a normal, retryable error instead.
constexpr int kTransferTimeoutMs = 15000;

// A reply that never received a body - a connection the gateway had already closed, a TLS
// handshake that failed, a request the transfer timeout aborted - finishes *closed*. Calling
// readAll() on it is harmless but makes Qt print "QIODevice::read (QNetworkReplyHttpImpl): device
// not open" for each one, which with several pages polling on a timer fills the log with warnings
// that say nothing the error handler below doesn't already report.
QJsonObject replyBody(QNetworkReply *reply) {
    if (!reply->isOpen())
        return {};
    return QJsonDocument::fromJson(reply->readAll()).object();
}
}

EuclidBaseClient::EuclidBaseClient(QObject *parent) : QObject(parent), m_baseUrl(QString::fromLatin1(kDefaultBaseUrl)) {}

void EuclidBaseClient::setBaseUrl(const QString &baseUrl) {
    if (baseUrl.isEmpty() || baseUrl == m_baseUrl)
        return;
    m_baseUrl = baseUrl;
    emit baseUrlChanged();

    const bool hadSession = !m_token.isEmpty();
    m_token.clear();
    m_namespace.clear();
    if (!m_accountId.isEmpty()) {
        m_accountId.clear();
        emit accountIdChanged();
    }
    if (!m_region.isEmpty()) {
        m_region.clear();
        emit regionChanged();
    }
    if (hadSession)
        emit sessionCleared();
}

void EuclidBaseClient::setAuthMode(const QString &authMode) {
    m_authMode = authMode;
}

void EuclidBaseClient::setAccessKey(const QString &accessKeyId, const QString &secretAccessKey) {
    m_accessKeyId = accessKeyId;
    m_secretAccessKey = secretAccessKey;
}

// Everything an authorized request needs to prove itself. The x-euclid-* headers are set here
// rather than at the call sites because both signature schemes cover them: a header added after
// signing would not be covered, and one changed afterwards would break the signature.
void EuclidBaseClient::authorize(QNetworkRequest &request, const QByteArray &body) {

    const QUrl url(m_baseUrl);
    // Same spelling Qt puts in the Host header, which is what the server signs against: the port
    // is only part of the authority when it isn't the scheme's default.
    const int defaultPort = url.scheme() == QLatin1String("https") ? 443 : 80;
    const int port = url.port(defaultPort);
    const QString authority = port == defaultPort ? url.host() : url.host() + ":" + QString::number(port);

    // Signed either way, so they go on the request before the signature is computed. account-id
    // and user-id are informational to the server - it resolves the caller from the key - but
    // RFC 9421 refuses to build a signature base over a component that is missing or empty.
    request.setRawHeader("x-euclid-region", m_region.toUtf8());
    request.setRawHeader("x-euclid-account-id", m_accountId.isEmpty() ? QByteArrayLiteral("-") : m_accountId.toUtf8());
    request.setRawHeader("x-euclid-user-id", m_userId.isEmpty() ? QByteArrayLiteral("-") : m_userId.toUtf8());
    if (!m_namespace.isEmpty())
        request.setRawHeader("x-euclid-namespace", m_namespace.toUtf8());

    const bool signing = (m_authMode == QLatin1String("sigv4") || m_authMode == QLatin1String("rfc9421"))
                         && !m_accessKeyId.isEmpty() && !m_secretAccessKey.isEmpty();
    if (!signing) {
        request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
        return;
    }

    RequestSigner::Request signable;
    signable.method = QStringLiteral("POST");
    signable.path = url.path().isEmpty() ? QStringLiteral("/") : url.path();
    signable.authority = authority;
    signable.body = body;
    for (const QByteArray &name: request.rawHeaderList())
        signable.headers.insert(QString::fromLatin1(name).toLower(), QString::fromUtf8(request.rawHeader(name)));
    signable.headers.insert(QStringLiteral("host"), authority);

    RequestSigner::Credentials credentials;
    credentials.accessKeyId = m_accessKeyId;
    credentials.secretAccessKey = m_secretAccessKey;
    credentials.region = m_region;
    // SigV4 scopes a signature to a service; the server re-derives the key from whatever the
    // credential scope names, so the routed module is the honest choice.
    credentials.service = QString::fromUtf8(request.rawHeader("x-euclid-target"));

    const auto signed_ = m_authMode == QLatin1String("sigv4")
                                 ? RequestSigner::signSigV4(signable, credentials)
                                 : RequestSigner::signRfc9421(signable, credentials);
    for (auto it = signed_.constBegin(); it != signed_.constEnd(); ++it)
        request.setRawHeader(it.key().toUtf8(), it.value().toUtf8());
}

void EuclidBaseClient::setBusy(const bool busy) {
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void EuclidBaseClient::post(const QString &target, const QString &action, const QJsonObject &body, bool authorized,
                             const std::function<void(const QJsonObject &)> &onSuccess,
                             const std::function<void(const QString &)> &onError) {
    QNetworkRequest request{QUrl(m_baseUrl)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("x-euclid-target", target.toUtf8());
    request.setRawHeader("x-euclid-action", action.toUtf8());
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    if (authorized) {
        authorize(request, payload);
    }

    // The local gateway runs with a self-signed dev certificate.
    QSslConfiguration sslConfig = request.sslConfiguration();
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(sslConfig);
    request.setTransferTimeout(kTransferTimeoutMs);

    QNetworkReply *reply = m_networkManager.post(request, payload);
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        const QJsonObject obj = replyBody(reply);

        if (reply->error() != QNetworkReply::NoError) {
            // euclid puts the reason in "error" (Core::HttpActionServer::ErrorResponse builds
            // {"error": ...}); "message" is tried first only because some responses have carried
            // it. Without the "error" fallback every server-side reason - "Invalid credentials",
            // "Namespace does not exist" - was replaced by Qt's generic transport string.
            const QString reason = obj.value("message").toString(obj.value("error").toString());
            onError(reason.isEmpty() ? reply->errorString() : reason);
            return;
        }
        onSuccess(obj);
    });
}

void EuclidBaseClient::postRaw(const QString &target, const QString &action, const QVariantMap &extraHeaders, const QByteArray &body,
                                const std::function<void(const QJsonObject &)> &onSuccess,
                                const std::function<void(const QString &)> &onError) {
    QNetworkRequest request{QUrl(m_baseUrl)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/octet-stream");
    request.setRawHeader("x-euclid-target", target.toUtf8());
    request.setRawHeader("x-euclid-action", action.toUtf8());
    // Extra headers first: they are part of the request the signature covers.
    for (auto it = extraHeaders.constBegin(); it != extraHeaders.constEnd(); ++it)
        request.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());
    authorize(request, body);

    // The local gateway runs with a self-signed dev certificate.
    QSslConfiguration sslConfig = request.sslConfiguration();
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(sslConfig);
    request.setTransferTimeout(kTransferTimeoutMs);

    QNetworkReply *reply = m_networkManager.post(request, body);
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        const QJsonObject obj = replyBody(reply);

        if (reply->error() != QNetworkReply::NoError) {
            // euclid puts the reason in "error" (Core::HttpActionServer::ErrorResponse builds
            // {"error": ...}); "message" is tried first only because some responses have carried
            // it. Without the "error" fallback every server-side reason - "Invalid credentials",
            // "Namespace does not exist" - was replaced by Qt's generic transport string.
            const QString reason = obj.value("message").toString(obj.value("error").toString());
            onError(reason.isEmpty() ? reply->errorString() : reason);
            return;
        }
        onSuccess(obj);
    });
}

void EuclidBaseClient::login(const QString &userId, const QString &password) {
    setBusy(true);

    QJsonObject body;
    if (userId.contains('@'))
        body["email"] = userId;
    else
        body["userId"] = userId;
    body["password"] = password;

    post("eam", "login", body, false,
         [this, userId](const QJsonObject &response) {
             m_userId = userId;
             const QJsonObject metadata = response.value("metadata").toObject();
             m_token = response.value("token").toString();
             m_accountId = metadata.value("accountId").toString();
             m_region = metadata.value("region").toString();

             emit accountIdChanged();
             emit regionChanged();
             emit loginSucceeded();
             fetchNamespaces();
         },
         [this](const QString &message) {
             setBusy(false);
             emit loginFailed(message);
         });
}

void EuclidBaseClient::fetchNamespaces() {
    setBusy(true);

    QJsonObject body;
    body["accountId"] = m_accountId;
    body["prefix"] = "";
    body["pageSize"] = 100;
    body["pageIndex"] = 0;
    body["sortColumn"] = "name";

    post("eam", "list-namespaces", body, true,
         [this](const QJsonObject &response) {
             setBusy(false);
             QStringList namespaces;
             const QJsonArray array = response.value("namespaces").toArray();
             for (const QJsonValue &value : array)
                 namespaces << value.toObject().value("name").toString();
             emit namespacesLoaded(namespaces);
         },
         [this](const QString &message) {
             setBusy(false);
             emit namespacesFailed(message);
         });
}

void EuclidBaseClient::setNamespace(const QString &namespaceName) {
    m_namespace = namespaceName;
}
