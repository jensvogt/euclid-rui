#include "EkmClient.h"
#include "EuclidBaseClient.h"

#include <QFile>
#include <QSaveFile>

namespace {
// Turns one "list-certificates"/"get-certificate" entry into the map the QML pages read. There is
// no private key in it: the server keeps that and it is not part of any response.
QVariantMap certificateToMap(const QJsonObject &certificate) {
    QVariantMap entry;
    entry["name"] = certificate.value("name").toString();
    entry["ern"] = certificate.value("ern").toString();
    entry["description"] = certificate.value("description").toString();
    // The PEM itself, which is what a "download" writes to a file.
    entry["certificate"] = certificate.value("certificate").toString();
    entry["subject"] = certificate.value("subject").toString();
    entry["issuer"] = certificate.value("issuer").toString();
    entry["serialNumber"] = certificate.value("serialNumber").toString();
    entry["fingerprint"] = certificate.value("fingerprint").toString();
    entry["subjectAltNames"] = certificate.value("subjectAltNames").toArray().toVariantList();
    // Whether euclid minted it itself rather than being given one. Kept apart from
    // subject == issuer on purpose: an imported certificate that happens to be self-signed is
    // still a decision somebody made. See Entity::EKM::Certificate::generated.
    entry["generated"] = certificate.value("generated").toBool();
    entry["notBefore"] = certificate.value("notBefore").toString();
    entry["notAfter"] = certificate.value("notAfter").toString();
    entry["tags"] = certificate.value("tags").toObject().toVariantMap();
    entry["created"] = certificate.value("created").toString();
    entry["modified"] = certificate.value("modified").toString();
    return entry;
}

// Reads a PEM file a QML FileDialog picked. Returns false and fills `error` rather than throwing,
// because the caller reports it the same way it reports a server refusal.
bool readTextFile(const QUrl &source, QString &contents, QString &error) {
    const QString path = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (path.isEmpty()) {
        error = QStringLiteral("No file was chosen.");
        return false;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("Cannot read %1: %2").arg(path, file.errorString());
        return false;
    }
    contents = QString::fromUtf8(file.readAll());
    if (contents.trimmed().isEmpty()) {
        error = QStringLiteral("%1 is empty.").arg(path);
        return false;
    }
    return true;
}
}// namespace

EkmClient::EkmClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EkmClient::fetchKeys(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ekm", "list-keys", body, true,
         [this](const QJsonObject &response) {
             QVariantList keys;
             for (const QJsonArray array = response.value("keys").toArray(); const auto &value : array) {
                 const QJsonObject key = value.toObject();
                 QVariantMap entry;
                 entry["name"] = key.value("name").toString();
                 entry["ern"] = key.value("ern").toString();
                 entry["algorithm"] = key.value("algorithm").toString();
                 entry["length"] = key.value("length").toInt();
                 entry["description"] = key.value("description").toString();
                 entry["tags"] = key.value("tags").toObject().toVariantMap();
                 entry["status"] = key.value("status").toString();
                 entry["created"] = key.value("created").toString();
                 entry["modified"] = key.value("modified").toString();
                 entry["deletionDate"] = key.value("deletionDate").toString();
                 keys << entry;
             }
             emit keysLoaded(keys, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit keysFailed(message);
         });
}

void EkmClient::createKey(const QString &algorithm, const int length) {
    QJsonObject body;
    body["algorithm"] = algorithm;
    body["length"] = length;

    m_base->post("ekm", "create-key", body, true,
         [this](const QJsonObject &response) {
             emit keyCreated(response.value("name").toString());
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyCreateFailed(message);
         });
}

void EkmClient::revokeKey(const QString &ern) {
    QJsonObject body;
    body["ern"] = ern;

    m_base->post("ekm", "revoke-key", body, true,
         [this](const QJsonObject &response) {
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyCreateFailed(message);
         });
}

void EkmClient::deleteKey(const QString &keyId, const int pendingWindowInDays) {
    QJsonObject body;
    body["keyId"] = keyId;
    body["pendingWindowInDays"] = pendingWindowInDays;

    m_base->post("ekm", "delete-key", body, true,
         [this](const QJsonObject &response) {
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyCreateFailed(message);
         });
}

void EkmClient::setKeyDescription(const QString &keyErn, const QString &description) {
    QJsonObject body;
    body["ern"] = keyErn;
    body["description"] = description;

    m_base->post("ekm", "set-key-description", body, true,
         [this, keyErn](const QJsonObject &response) {
             // Reported as the server stored it rather than as it was sent, so a view shows what
             // the key actually reads.
             emit keyDescriptionChanged(keyErn, response.value("description").toString());
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyDescriptionFailed(message);
         });
}

void EkmClient::addKeyTag(const QString &keyErn, const QString &key, const QString &value) {
    QJsonObject body;
    body["ern"] = keyErn;
    body["key"] = key;
    body["value"] = value;

    m_base->post("ekm", "add-key-tag", body, true,
         [this, keyErn, key, value](const QJsonObject &response) {
             emit keyTagAdded(keyErn, key, value);
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyTagAddFailed(message);
         });
}

void EkmClient::deleteKeyTag(const QString &keyErn, const QString &key) {
    QJsonObject body;
    body["ern"] = keyErn;
    body["key"] = key;

    m_base->post("ekm", "delete-key-tag", body, true,
         [this, keyErn, key](const QJsonObject &response) {
             emit keyTagDeleted(keyErn, key);
             emit keysReload();
         },
         [this](const QString &message) {
             emit keyTagDeleteFailed(message);
         });
}

// ── Certificates ────────────────────────────────────────────────────────────

void EkmClient::fetchCertificates(const QString &prefix, const int pageIndex, const int pageSize,
                                  const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("ekm", "list-certificates", body, true,
         [this](const QJsonObject &response) {
             QVariantList certificates;
             for (const QJsonArray array = response.value("certificates").toArray(); const auto &value: array)
                 certificates << certificateToMap(value.toObject());
             emit certificatesLoaded(certificates, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit certificatesFailed(message);
         });
}

void EkmClient::fetchCertificate(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("ekm", "get-certificate", body, true,
         [this, name](const QJsonObject &response) {
             emit certificateLoaded(name, certificateToMap(response.value("certificate").toObject()));
         },
         [this](const QString &message) {
             emit certificatesFailed(message);
         });
}

void EkmClient::createCertificate(const QString &name, const QString &commonName, const QStringList &subjectAltNames,
                                  const int validDays, const int keyBits, const QString &description) {
    QJsonObject body;
    body["name"] = name;
    body["description"] = description;
    body["commonName"] = commonName;
    QJsonArray names;
    for (const QString &altName: subjectAltNames)
        names.append(altName);
    body["subjectAltNames"] = names;
    body["validDays"] = validDays;
    body["keyBits"] = keyBits;

    m_base->post("ekm", "create-certificate", body, true,
         [this, name](const QJsonObject &response) {
             emit certificateCreated(name, certificateToMap(response.value("certificate").toObject()));
             emit certificatesReload();
         },
         [this](const QString &message) {
             emit certificateCreateFailed(message);
         });
}

void EkmClient::importCertificate(const QString &name, const QString &description,
                                  const QUrl &certificateFile, const QUrl &privateKeyFile) {
    QString certificatePem;
    QString privateKeyPem;
    QString error;
    // Both read before anything is sent, so a mistyped key path is reported as such rather than
    // as a half-finished import.
    if (!readTextFile(certificateFile, certificatePem, error)) {
        emit certificateImportFailed(error);
        return;
    }
    if (!readTextFile(privateKeyFile, privateKeyPem, error)) {
        emit certificateImportFailed(error);
        return;
    }

    QJsonObject body;
    body["name"] = name;
    body["description"] = description;
    body["certificate"] = certificatePem;
    body["privateKey"] = privateKeyPem;

    m_base->post("ekm", "import-certificate", body, true,
         [this, name](const QJsonObject &response) {
             emit certificateImported(name, certificateToMap(response.value("certificate").toObject()));
             emit certificatesReload();
         },
         [this](const QString &message) {
             emit certificateImportFailed(message);
         });
}

void EkmClient::exportCertificate(const QString &name, const QUrl &targetFile) {
    const QString path = targetFile.isLocalFile() ? targetFile.toLocalFile() : targetFile.toString();
    if (path.isEmpty()) {
        emit certificateExportFailed(QStringLiteral("No file was chosen."));
        return;
    }

    // Fetched rather than written out of whatever the table happens to be holding: the listing is
    // a snapshot, and what gets saved to disk should be what the server has now.
    QJsonObject body;
    body["name"] = name;

    m_base->post("ekm", "get-certificate", body, true,
         [this, name, path](const QJsonObject &response) {
             const QString pem = response.value("certificate").toObject().value("certificate").toString();
             if (pem.isEmpty()) {
                 emit certificateExportFailed(QStringLiteral("Certificate '%1' has no PEM to save.").arg(name));
                 return;
             }
             // QSaveFile: nothing half-written is left behind if the write fails, so an existing
             // file is not destroyed by a failed overwrite of it.
             QSaveFile file(path);
             if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
                 emit certificateExportFailed(QStringLiteral("Cannot write %1: %2").arg(path, file.errorString()));
                 return;
             }
             file.write(pem.toUtf8());
             if (!file.commit()) {
                 emit certificateExportFailed(QStringLiteral("Cannot write %1: %2").arg(path, file.errorString()));
                 return;
             }
             emit certificateExported(name, path);
         },
         [this](const QString &message) {
             emit certificateExportFailed(message);
         });
}

void EkmClient::deleteCertificate(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("ekm", "delete-certificate", body, true,
         [this, name](const QJsonObject &response) {
             emit certificateDeleted(name);
             emit certificatesReload();
         },
         [this](const QString &message) {
             emit certificateDeleteFailed(message);
         });
}
