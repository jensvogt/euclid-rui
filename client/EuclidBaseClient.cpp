#include "EuclidBaseClient.h"

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
    if (authorized) {
        request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
        request.setRawHeader("x-euclid-region", m_region.toUtf8());
        if (!m_namespace.isEmpty())
            request.setRawHeader("x-euclid-namespace", m_namespace.toUtf8());
    }

    // The local gateway runs with a self-signed dev certificate.
    QSslConfiguration sslConfig = request.sslConfiguration();
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(sslConfig);
    request.setTransferTimeout(kTransferTimeoutMs);

    QNetworkReply *reply = m_networkManager.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
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
    request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    request.setRawHeader("x-euclid-region", m_region.toUtf8());
    if (!m_namespace.isEmpty())
        request.setRawHeader("x-euclid-namespace", m_namespace.toUtf8());
    for (auto it = extraHeaders.constBegin(); it != extraHeaders.constEnd(); ++it)
        request.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());

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
         [this](const QJsonObject &response) {
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
