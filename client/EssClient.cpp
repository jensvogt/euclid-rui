#include "EssClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>

namespace {
// Turns one "list-secrets"/"create-secret"/"update-secret" entry into the map the QML pages read.
// There is no value in it, for the same reason there is none in the server's Secret DTO: the map
// has nowhere to put one, so no page can end up displaying a plaintext it did not ask for.
QVariantMap secretToMap(const QJsonObject &secret) {
    QVariantMap entry;
    entry["name"] = secret.value("name").toString();
    entry["ern"] = secret.value("ern").toString();
    entry["description"] = secret.value("description").toString();
    // The EKM key the value is encrypted under. A secret whose key is revoked or gone can still be
    // read, so this is worth showing: it is what says which key a rotation would have to move off.
    entry["encryptionKeyErn"] = secret.value("encryptionKeyErn").toString();
    // How many times the value has been set, counting the first.
    entry["version"] = static_cast<qlonglong>(secret.value("version").toDouble());
    entry["rotated"] = secret.value("rotated").toString();
    entry["tags"] = secret.value("tags").toObject().toVariantMap();
    entry["created"] = secret.value("created").toString();
    entry["modified"] = secret.value("modified").toString();
    return entry;
}
}// namespace

EssClient::EssClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EssClient::fetchSecrets(const QString &prefix, const int pageIndex, const int pageSize,
                             const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ess", "list-secrets", body, true,
         [this](const QJsonObject &response) {
             QVariantList secrets;
             for (const QJsonArray array = response.value("secrets").toArray(); const auto &value: array)
                 secrets << secretToMap(value.toObject());
             emit secretsLoaded(secrets, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit secretsFailed(message);
         });
}

void EssClient::fetchSecretValue(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("ess", "get-secret", body, true,
         [this, name](const QJsonObject &response) {
             emit secretValueLoaded(name, response.value("value").toString(),
                                    secretToMap(response.value("secret").toObject()));
         },
         [this, name](const QString &message) {
             emit secretValueFailed(name, message);
         });
}

void EssClient::createSecret(const QString &name, const QString &value, const QString &description, const QString &keyErn) {
    QJsonObject body;
    body["name"] = name;
    body["value"] = value;
    body["description"] = description;
    // Empty is meaningful: it asks the module for the namespace's own secrets key rather than
    // naming one, so it is sent as it is rather than left out.
    body["keyErn"] = keyErn;

    m_base->post("ess", "create-secret", body, true,
         [this, name](const QJsonObject &response) {
             emit secretCreated(name, secretToMap(response.value("secret").toObject()));
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretCreateFailed(message);
         });
}

// The three calls below are all "update-secret". They are kept apart because the server tells a
// rotation from a change of description by which fields the request mentions at all - an absent
// field means "leave this alone", and an empty one is a value somebody chose. So each sends only
// what it means to change.
void EssClient::rotateSecret(const QString &name, const QString &value) {
    QJsonObject body;
    body["name"] = name;
    body["value"] = value;

    m_base->post("ess", "update-secret", body, true,
         [this, name](const QJsonObject &response) {
             emit secretRotated(name, secretToMap(response.value("secret").toObject()));
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretRotateFailed(message);
         });
}

void EssClient::setSecretDescription(const QString &name, const QString &description) {
    QJsonObject body;
    body["name"] = name;
    body["description"] = description;

    m_base->post("ess", "update-secret", body, true,
         [this, name](const QJsonObject &response) {
             // Reported as the server stored it rather than as it was sent, so a view shows what
             // the secret actually reads.
             emit secretDescriptionChanged(name, response.value("secret").toObject().value("description").toString());
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretDescriptionFailed(message);
         });
}

void EssClient::reKeySecret(const QString &name, const QString &keyErn) {
    QJsonObject body;
    body["name"] = name;
    body["keyErn"] = keyErn;

    m_base->post("ess", "update-secret", body, true,
         [this, name](const QJsonObject &response) {
             emit secretReKeyed(name, secretToMap(response.value("secret").toObject()));
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretReKeyFailed(message);
         });
}

void EssClient::deleteSecret(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("ess", "delete-secret", body, true,
         [this, name](const QJsonObject &response) {
             emit secretDeleted(name);
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretDeleteFailed(message);
         });
}

void EssClient::addSecretTag(const QString &name, const QString &key, const QString &value) {
    QJsonObject body;
    body["name"] = name;
    body["key"] = key;
    body["value"] = value;

    m_base->post("ess", "add-secret-tag", body, true,
         [this, name, key, value](const QJsonObject &response) {
             emit secretTagAdded(name, key, value);
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretTagAddFailed(message);
         });
}

void EssClient::deleteSecretTag(const QString &name, const QString &key) {
    QJsonObject body;
    body["name"] = name;
    body["key"] = key;

    m_base->post("ess", "delete-secret-tag", body, true,
         [this, name, key](const QJsonObject &response) {
             emit secretTagDeleted(name, key);
             emit secretsReload();
         },
         [this](const QString &message) {
             emit secretTagDeleteFailed(message);
         });
}
