#include "EuclidBaseClient.h"
#include <algorithm>
#include <QDateTime>
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

EuclidBaseClient::EuclidBaseClient(QObject *parent) : QObject(parent), m_baseUrl(QString::fromLatin1(kDefaultBaseUrl)) {
    m_sessionRefreshTimer.setSingleShot(true);
    connect(&m_sessionRefreshTimer, &QTimer::timeout, this, &EuclidBaseClient::refreshSession);
}

// The "exp" claim, read out of the JWT's payload without verifying anything. A JWT is three
// base64url segments; the middle one is the claims, and the only claim needed here is when this
// stops being accepted. Verifying it would need the signing secret, which is the server's alone -
// and there is nothing to protect against: a client lying to itself about its own expiry only
// renews at the wrong moment.
qint64 EuclidBaseClient::secondsUntilExpiry(const QString &token) {
    const auto segments = token.split(QLatin1Char('.'));
    if (segments.size() < 2)
        return -1;

    const auto payload = QByteArray::fromBase64(segments.at(1).toUtf8(), QByteArray::Base64UrlEncoding);
    const auto claims = QJsonDocument::fromJson(payload).object();
    const auto expiry = claims.value(QStringLiteral("exp"));
    if (!expiry.isDouble())
        return -1;

    return static_cast<qint64>(expiry.toDouble()) - QDateTime::currentSecsSinceEpoch();
}

void EuclidBaseClient::scheduleSessionRefresh() {

    m_sessionRefreshTimer.stop();
    if (m_token.isEmpty())
        return;

    // Nothing to renew while requests are signed: the token is not sent, so its expiry decides
    // nothing. Asking anyway would be an hourly request that buys nothing - and an hourly failure
    // reported to the user on any server without refresh-session, for a session that is working
    // perfectly well. The mirror of authorize()'s own condition, deliberately: whether the token
    // matters is exactly whether it would be sent.
    if (m_authMode == QLatin1String("rfc9421") && !m_accessKeyId.isEmpty() && !m_secretAccessKey.isEmpty())
        return;

    const auto remaining = secondsUntilExpiry(m_token);
    if (remaining < 0) {
        // No usable expiry: either not a JWT or a claim this cannot read. Renewing on a guess would
        // be worse than not renewing - the session still works until it does not, which is where
        // this started.
        return;
    }

    // A minute of headroom, or half the lifetime for a session short enough that a minute is most
    // of it. Early rather than late on purpose: refresh-session authenticates like every other
    // action, so a token that has already expired cannot be used to ask for its successor.
    const qint64 lead = std::min<qint64>(60, remaining / 2);
    const qint64 delay = std::max<qint64>(1, remaining - lead);

    m_sessionRefreshTimer.start(static_cast<int>(std::min<qint64>(delay, 24 * 60 * 60) * 1000));
}

void EuclidBaseClient::refreshSession() {

    if (m_token.isEmpty() || m_refreshingSession)
        return;
    m_refreshingSession = true;

    // Not marked busy: this is the application keeping itself alive rather than anything the user
    // asked for, and a spinner appearing once an hour for no reason somebody can see is worse than
    // no spinner.
    post("eam", "refresh-session", QJsonObject{}, true,
         [this](const QJsonObject &response) {
             m_refreshingSession = false;

             const auto token = response.value("token").toString();
             if (token.isEmpty()) {
                 emit sessionRefreshFailed(tr("The gateway renewed the session without giving a token."));
                 return;
             }
             m_token = token;

             // The key comes back with it, and may have been reissued since - adopted for the same
             // reason login adopts it.
             if (const auto accessKeyId = response.value("accessKeyId").toString(),
                 secretAccessKey = response.value("secretAccessKey").toString();
                 !accessKeyId.isEmpty() && !secretAccessKey.isEmpty()) {
                 setAccessKey(accessKeyId, secretAccessKey);
                 emit accessKeyIssued(accessKeyId, secretAccessKey);
             }

             scheduleSessionRefresh();
             emit sessionRefreshed(secondsUntilExpiry(m_token));
         },
         [this](const QString &message) {
             m_refreshingSession = false;
             // Tried again once, sooner: a renewal that failed because the gateway was briefly
             // unreachable should not cost the whole session, and there is still headroom left
             // before the token actually expires.
             const auto remaining = secondsUntilExpiry(m_token);
             if (remaining > 10) {
                 m_sessionRefreshTimer.start(static_cast<int>(std::min<qint64>(remaining - 5, 30) * 1000));
                 return;
             }
             emit sessionRefreshFailed(message);
         });
}

void EuclidBaseClient::setBaseUrl(const QString &baseUrl) {
    if (baseUrl.isEmpty() || baseUrl == m_baseUrl)
        return;
    m_baseUrl = baseUrl;
    emit baseUrlChanged();

    const bool hadSession = !m_token.isEmpty();
    m_token.clear();
    // The session this was renewing is gone; renewing it against another gateway would be asking a
    // backend about a token it never minted.
    m_sessionRefreshTimer.stop();
    m_namespace.clear();
    if (m_isAdmin) {
        m_isAdmin = false;
        emit isAdminChanged();
    }
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
void EuclidBaseClient::authorize(QNetworkRequest &request, const QByteArray &body) const {

    const QUrl url(m_baseUrl);
    // Same spelling Qt puts in the Host header, which is what the server signs against: the port
    // is only part of the authority when it isn't the scheme's default.
    const int defaultPort = url.scheme() == QLatin1String("https") ? 443 : 80;
    const int port = url.port(defaultPort);
    const QString authority = port == defaultPort ? url.host() : url.host() + ":" + QString::number(port);

    // Signed either way, so they go on the request before the signature is computed. region,
    // account-id and user-id are informational to the server - it resolves the caller from the key
    // - but RFC 9421 refuses to build a signature base over a component that is missing or empty
    // (see RequestSigner::rfc9421Components()), so all three carry a placeholder rather than
    // nothing. region was the one that did not, and a login whose metadata carries no region left
    // every signed request unverifiable: the server cannot build the base, falls through to the
    // next scheme, and reports the one it ended on - "Missing or invalid bearer token", for a
    // request that never claimed to have a token.
    request.setRawHeader("x-euclid-region", m_region.isEmpty() ? QByteArrayLiteral("-") : m_region.toUtf8());
    request.setRawHeader("x-euclid-account-id", m_accountId.isEmpty() ? QByteArrayLiteral("-") : m_accountId.toUtf8());
    request.setRawHeader("x-euclid-user-id", m_userId.isEmpty() ? QByteArrayLiteral("-") : m_userId.toUtf8());
    if (!m_namespace.isEmpty())
        request.setRawHeader("x-euclid-namespace", m_namespace.toUtf8());

    const bool signing = m_authMode == QLatin1String("rfc9421")
                         && !m_accessKeyId.isEmpty() && !m_secretAccessKey.isEmpty();

    // Which scheme this request ended up on, and the state that decided it. Worth saying out loud
    // because the choice is silent otherwise: a signature mode with no key configured sends a
    // bearer token instead, and the server's refusal names the scheme it checked last rather than
    // the one that was meant.
    qCDebug(lcAuth).noquote() << (signing ? "rfc9421" : "bearer")
                              << QStringLiteral("target=%1 action=%2 authority=%3")
                                         .arg(QString::fromUtf8(request.rawHeader("x-euclid-target")),
                                              QString::fromUtf8(request.rawHeader("x-euclid-action")), authority);
    qCDebug(lcAuth).noquote() << QStringLiteral("  authMode=%1 region=%2 account=%3 user=%4 namespace=%5")
                                         .arg(m_authMode, m_region.isEmpty() ? QStringLiteral("(empty)") : m_region,
                                              m_accountId.isEmpty() ? QStringLiteral("(empty)") : m_accountId,
                                              m_userId.isEmpty() ? QStringLiteral("(empty)") : m_userId,
                                              m_namespace.isEmpty() ? QStringLiteral("(empty)") : m_namespace);

    if (!signing) {
        request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
        // The token itself is a credential and stays out of the log; its length and how much life
        // it has left are what distinguish "not sent" from "expired", which is the whole question
        // when a bearer request comes back refused.
        qCDebug(lcAuth).noquote() << QStringLiteral("  token=%1 bytes, expires in %2 s")
                                             .arg(m_token.size())
                                             .arg(secondsUntilExpiry(m_token));
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
    // Carried for the credential scope; the server re-derives the key from whatever that scope
    // names, so the routed module is the honest choice.
    credentials.service = QString::fromUtf8(request.rawHeader("x-euclid-target"));

    // RFC 9421 is the only scheme the RUI signs with. SigV4 proved the same thing with the same
    // key and the server still accepts it, but there is no reason to send a proprietary
    // canonicalisation where an open standard says it as well.
    const auto signed_ = RequestSigner::signRfc9421(signable, credentials);
    for (auto it = signed_.constBegin(); it != signed_.constEnd(); ++it)
        request.setRawHeader(it.key().toUtf8(), it.value().toUtf8());

    // The key id is public - it is sent in the clear as `keyid` - so it is named here: a signature
    // refused because the key belongs to another installation looks exactly like one refused for a
    // bad base, and this is what tells the two apart.
    qCDebug(lcAuth).noquote() << QStringLiteral("  keyid=%1").arg(credentials.accessKeyId);
    qCDebug(lcAuth).noquote() << QStringLiteral("  signature-input=%1").arg(signed_.value(QStringLiteral("Signature-Input")));
}

void EuclidBaseClient::setBusy(const bool busy) {
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

QNetworkReply *EuclidBaseClient::post(const QString &target, const QString &action, const QJsonObject &body, const bool authorized,
                             const std::function<void(const QJsonObject &)> &onSuccess,
                             const std::function<void(const QString &)> &onError,
                             const int timeoutMs) {
    QNetworkRequest request{QUrl(m_baseUrl)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("x-euclid-target", target.toUtf8());
    request.setRawHeader("x-euclid-action", action.toUtf8());

    // Listing something is the UI describing the system, not asking it to do work, and every page
    // here re-lists on a timer for as long as it is open. Counted as load, a browser left on the
    // queues page would hold EQS at whatever size it had reached and stop it ever scaling down -
    // the monitoring preventing the thing it exists to watch.
    //
    // Everything else the RUI sends is a person doing something: creating a queue, publishing a
    // message, stopping an application. Those are real, and are counted. Deliberately not signed
    // (see RequestSigner's covered components) - it is a hint about intent, not a credential.
    if (action.startsWith(QLatin1String("list"))) {
        request.setRawHeader("x-euclid-internal", "true");
    }
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    if (authorized) {
        authorize(request, payload);
    }

    // The local gateway runs with a self-signed dev certificate.
    QSslConfiguration sslConfig = request.sslConfiguration();
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(sslConfig);
    request.setTransferTimeout(timeoutMs > 0 ? timeoutMs : kTransferTimeoutMs);

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
    return reply;
}

QNetworkReply *EuclidBaseClient::postRaw(const QString &target, const QString &action, const QVariantMap &extraHeaders, const QByteArray &body,
                                const std::function<void(const QJsonObject &)> &onSuccess,
                                const std::function<void(const QString &)> &onError,
                                const int timeoutMs) {
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
    request.setTransferTimeout(timeoutMs > 0 ? timeoutMs : kTransferTimeoutMs);

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
    return reply;
}

QNetworkReply *EuclidBaseClient::postForBytes(const QString &target, const QString &action, const QVariantMap &extraHeaders,
                                const std::function<void(const QByteArray &)> &onSuccess,
                                const std::function<void(const QString &)> &onError,
                                const int timeoutMs) {
    QNetworkRequest request{QUrl(m_baseUrl)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/octet-stream");
    request.setRawHeader("x-euclid-target", target.toUtf8());
    request.setRawHeader("x-euclid-action", action.toUtf8());
    for (auto it = extraHeaders.constBegin(); it != extraHeaders.constEnd(); ++it)
        request.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());
    authorize(request, {});

    // The local gateway runs with a self-signed dev certificate.
    QSslConfiguration sslConfig = request.sslConfiguration();
    sslConfig.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(sslConfig);
    request.setTransferTimeout(timeoutMs > 0 ? timeoutMs : kTransferTimeoutMs);

    QNetworkReply *reply = m_networkManager.post(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        // Read once: the body is either the payload or the JSON explaining its absence, and a
        // reply cannot be read twice.
        const QByteArray body = reply->isOpen() ? reply->readAll() : QByteArray();

        if (reply->error() != QNetworkReply::NoError) {
            const QJsonObject obj = QJsonDocument::fromJson(body).object();
            const QString reason = obj.value("message").toString(obj.value("error").toString());
            onError(reason.isEmpty() ? reply->errorString() : reason);
            return;
        }
        onSuccess(body);
    });
    return reply;
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
             m_isAdmin = response.value("isAdmin").toBool();

             // The access key the server just handed back for this user, adopted rather than
             // ignored. Every authorized request is signed with a key; login is the one call that
             // is not - so a key belonging to some other installation costs nothing until the
             // moment login succeeds, and then fails every request that follows it. Pointing the
             // RUI at a second gateway is exactly that case: the key in the settings was typed for
             // the first one, and the second has never heard of it.
             //
             // Stable across logins, so this is not key churn: EAM reuses the user's existing
             // active key and mints one only when there is none (see EamServer's issueSession).
             if (const auto accessKeyId = response.value("accessKeyId").toString(),
                 secretAccessKey = response.value("secretAccessKey").toString();
                 !accessKeyId.isEmpty() && !secretAccessKey.isEmpty()) {
                 setAccessKey(accessKeyId, secretAccessKey);
                 // Said rather than stored here: what is on disk is AppSettings' business, and it
                 // is the settings page's value that would otherwise go on showing a key this
                 // session has stopped using.
                 emit accessKeyIssued(accessKeyId, secretAccessKey);
             }

             // Renewal starts with the session rather than when something first fails: a token is
             // good for an hour, and the point is to replace it while it still works.
             scheduleSessionRefresh();

             emit isAdminChanged();
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
