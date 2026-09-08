#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class EuclidBaseClient;

// ESS (secrets store) calls: the passwords, connection strings and tokens the things euclid runs
// need, each encrypted under an EKM key before it is stored.
//
// One rule shapes this class, and it is the server's: a value leaves euclid through "get-secret"
// and nothing else. So the listing carries metadata only, nothing here keeps a plaintext in a
// member, and fetchSecretValue() hands what it read straight to one signal - the page that asked
// for it owns it from there and is the only thing holding it.
class EssClient : public QObject {
    Q_OBJECT

public:
    explicit EssClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // Paged and sorted server-side over the stored fields: name, ern, description, version,
    // rotated, created, modified. "rotated" is the one worth sorting on - it is what answers which
    // secrets nobody has changed in a year.
    Q_INVOKABLE void fetchSecrets(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                  const QString &sortColumn = QStringLiteral("name"),
                                  const QString &sortDirection = QStringLiteral("asc"));

    // The one call that decrypts anything. Every read is logged server-side with who asked, which
    // is the reason it is a deliberate action here rather than something the table does for every
    // row it draws.
    Q_INVOKABLE void fetchSecretValue(const QString &name);

    // An empty keyErn asks ESS for the namespace's own secrets key, which it creates the first
    // time something needs one. A name that already exists is refused rather than overwritten -
    // rotateSecret() is the call that means to replace a value.
    Q_INVOKABLE void createSecret(const QString &name, const QString &value,
                                  const QString &description = QString(), const QString &keyErn = QString());

    // A rotation: the version moves on and the previous value is gone. Sends "value" alone, since
    // "update-secret" changes exactly what the request mentions and an absent field is what tells
    // the server to leave the rest as it is.
    Q_INVOKABLE void rotateSecret(const QString &name, const QString &value);

    // Replaces the free text saying what the secret is for. An empty description is a valid one
    // and clears whatever was there, which is why it is sent even when empty.
    Q_INVOKABLE void setSecretDescription(const QString &name, const QString &description);

    // Re-encrypts the stored value under another EKM key without changing it: the version and the
    // rotation date stay put, because how a secret is protected is not what it is. This is how a
    // secret is moved off a key that is being retired.
    Q_INVOKABLE void reKeySecret(const QString &name, const QString &keyErn);

    Q_INVOKABLE void deleteSecret(const QString &name);

    // Upserts the tag unconditionally (there is no set-secret-tag counterpart server-side).
    Q_INVOKABLE void addSecretTag(const QString &name, const QString &key, const QString &value);
    // No-ops server-side if the secret doesn't have this tag key.
    Q_INVOKABLE void deleteSecretTag(const QString &name, const QString &key);

signals:
    // Each entry: {name, ern, description, encryptionKeyErn, version, rotated, tags, created,
    // modified}. There is no value in it: list-secrets does not answer with one, and this does not
    // invent a field that a table would then be holding.
    void secretsLoaded(const QVariantList &secrets, int total);
    void secretsFailed(const QString &message);
    void secretsReload();

    // The decrypted value, alongside the metadata the same response carried. Whoever connects to
    // this is holding the only copy - nothing here keeps one.
    void secretValueLoaded(const QString &name, const QString &value, const QVariantMap &secret);
    void secretValueFailed(const QString &name, const QString &message);

    void secretCreated(const QString &name, const QVariantMap &secret);
    void secretCreateFailed(const QString &message);
    void secretRotated(const QString &name, const QVariantMap &secret);
    void secretRotateFailed(const QString &message);
    void secretDescriptionChanged(const QString &name, const QString &description);
    void secretDescriptionFailed(const QString &message);
    void secretReKeyed(const QString &name, const QVariantMap &secret);
    void secretReKeyFailed(const QString &message);
    void secretDeleted(const QString &name);
    void secretDeleteFailed(const QString &message);
    void secretTagAdded(const QString &name, const QString &key, const QString &value);
    void secretTagAddFailed(const QString &message);
    void secretTagDeleted(const QString &name, const QString &key);
    void secretTagDeleteFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
