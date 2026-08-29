#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QUrl>

namespace {
constexpr auto kBaseUrl = "https://localhost:5566/";
}

EuclidBaseClient::EuclidBaseClient(QObject *parent) : QObject(parent) {}

void EuclidBaseClient::setBusy(const bool busy) {
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void EuclidBaseClient::post(const QString &target, const QString &action, const QJsonObject &body, bool authorized,
                             const std::function<void(const QJsonObject &)> &onSuccess,
                             const std::function<void(const QString &)> &onError) {
    QNetworkRequest request{QUrl(kBaseUrl)};
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

    QNetworkReply *reply = m_networkManager.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        const QByteArray data = reply->readAll();
        const QJsonObject obj = QJsonDocument::fromJson(data).object();

        if (reply->error() != QNetworkReply::NoError) {
            onError(obj.value("message").toString(reply->errorString()));
            return;
        }
        onSuccess(obj);
    });
}

void EuclidBaseClient::postRaw(const QString &target, const QString &action, const QVariantMap &extraHeaders, const QByteArray &body,
                                const std::function<void(const QJsonObject &)> &onSuccess,
                                const std::function<void(const QString &)> &onError) {
    QNetworkRequest request{QUrl(kBaseUrl)};
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

    QNetworkReply *reply = m_networkManager.post(request, body);
    connect(reply, &QNetworkReply::finished, this, [reply, onSuccess, onError]() {
        reply->deleteLater();
        const QByteArray data = reply->readAll();
        const QJsonObject obj = QJsonDocument::fromJson(data).object();

        if (reply->error() != QNetworkReply::NoError) {
            onError(obj.value("message").toString(reply->errorString()));
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
