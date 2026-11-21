#include "EssClient.h"

#include <memory>
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
                             const QString &sortColumn, const QString &sortDirection, const QString &matchType) {
    QJsonObject body;
    body["prefix"] = prefix;
    EuclidBaseClient::addMatchType(body, matchType);
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

void EssClient::copySecret(const QString &sourceName, const QString &newName, const QString &description) {
    copySecretThen(sourceName, newName, description,
        [this, sourceName, newName](const int tagsFailed) {
            emit secretCopied(sourceName, newName, tagsFailed);
            emit secretsReload();
        },
        [this, sourceName](const QString &message) { emit secretCopyFailed(sourceName, message); });
}

void EssClient::renameSecret(const QString &sourceName, const QString &newName) {
    copySecretThen(sourceName, newName, QString(),
        [this, sourceName, newName](const int tagsFailed) {
            if (tagsFailed > 0) {
                // Not deleted: the copy is short of tags the original still has.
                emit secretRenameFailed(sourceName, QString::number(tagsFailed) + " tag(s) could not be copied to "
                                        + newName + ", so " + sourceName + " was kept.", true);
                emit secretsReload();
                return;
            }
            QJsonObject body;
            body["name"] = sourceName;
            m_base->post("ess", "delete-secret", body, true,
                 [this, sourceName, newName](const QJsonObject &) {
                     emit secretRenamed(sourceName, newName);
                     emit secretsReload();
                 },
                 [this, sourceName, newName](const QString &message) {
                     emit secretRenameFailed(sourceName, newName + " was created, but " + sourceName
                                             + " could not be deleted: " + message, true);
                     emit secretsReload();
                 });
        },
        [this, sourceName](const QString &message) { emit secretRenameFailed(sourceName, message, false); });
}

void EssClient::copySecretThen(const QString &sourceName, const QString &newName, const QString &description,
                               const std::function<void(int)> &onDone, const std::function<void(const QString &)> &onFail) {
    QJsonObject readBody;
    readBody["name"] = sourceName;

    // Posted directly rather than through fetchSecretValue(): that one announces the value to
    // whoever listens for a reveal - the details page - and this read is not one.
    m_base->post("ess", "get-secret", readBody, true,
         [this, newName, description, onDone, onFail](const QJsonObject &response) {
             const QVariantMap source = secretToMap(response.value("secret").toObject());

             QJsonObject createBody;
             createBody["name"] = newName;
             createBody["value"] = response.value("value").toString();
             createBody["description"] = description.isEmpty() ? source.value("description").toString() : description;
             // The same key, so the copy is sealed exactly as the original is.
             createBody["keyErn"] = source.value("encryptionKeyErn").toString();
             const QVariantMap tags = source.value("tags").toMap();

             m_base->post("ess", "create-secret", createBody, true,
                  [this, newName, tags, onDone](const QJsonObject &) {
                      if (tags.isEmpty()) {
                          onDone(0);
                          return;
                      }
                      // One request per tag; done once the last has answered.
                      auto remaining = std::make_shared<int>(static_cast<int>(tags.size()));
                      auto failed = std::make_shared<int>(0);
                      for (auto it = tags.cbegin(); it != tags.cend(); ++it) {
                          QJsonObject tagBody;
                          tagBody["name"] = newName;
                          tagBody["key"] = it.key();
                          tagBody["value"] = it.value().toString();
                          const auto done = [remaining, failed, onDone]() {
                              if (--*remaining > 0) return;
                              onDone(*failed);
                          };
                          m_base->post("ess", "add-secret-tag", tagBody, true,
                               [done](const QJsonObject &) { done(); },
                               [done, failed](const QString &) { ++*failed; done(); });
                      }
                  },
                  onFail);
         },
         onFail);
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
