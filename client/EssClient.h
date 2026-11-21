#pragma once

#include <functional>

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
                                  const QString &sortDirection = QStringLiteral("asc"),
                                  const QString &matchType = QString());

    // The one call that decrypts anything. Every read is logged server-side with who asked, which
    // is the reason it is a deliberate action here rather than something the table does for every
    // row it draws.
    Q_INVOKABLE void fetchSecretValue(const QString &name);

    // An empty keyErn asks ESS for the namespace's own secrets key, which it creates the first
    // time something needs one. A name that already exists is refused rather than overwritten -
    // rotateSecret() is the call that means to replace a value.
    Q_INVOKABLE void createSecret(const QString &name, const QString &value,
                                  const QString &description = QString(), const QString &keyErn = QString());

    // A new secret holding what `sourceName` holds: its value, description, EKM key and tags. ESS
    // has no copy of its own, so this is three steps - get-secret (a read of the value, audited as
    // one), create-secret under `newName`, then one add-secret-tag per tag. The value goes from
    // one call to the next and nowhere else. `description` replaces the source's when not empty.
    // A name that exists already is refused by create-secret, as it would be by hand.
    Q_INVOKABLE void copySecret(const QString &sourceName, const QString &newName,
                                const QString &description = QString());

    // ESS cannot rename either, so this is copySecret() followed by delete-secret of the source -
    // and the source is only deleted once the copy is whole, tags included. Not a rename to
    // anything that held on to the old one: the ERN is the name's, so grants written against the
    // old ERN no longer match, and the version count and created date start again.
    Q_INVOKABLE void renameSecret(const QString &sourceName, const QString &newName);

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
    // `tagsFailed` counts tags that could not be copied - the secret itself exists by then, so it
    // is reported as done, with what is missing, rather than as a failure.
    void secretCopied(const QString &sourceName, const QString &newName, int tagsFailed);
    void secretCopyFailed(const QString &sourceName, const QString &message);
    void secretRenamed(const QString &oldName, const QString &newName);
    // `copied` is true when the new secret exists but the old one is still there too - the copy
    // went through and the delete (or a tag) did not, so there are two until somebody removes one.
    void secretRenameFailed(const QString &oldName, const QString &message, bool copied);
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
    // The copy itself, shared by copySecret() and renameSecret(): `onDone` gets the number of tags
    // that could not be copied, `onFail` the message when the secret itself was not created.
    void copySecretThen(const QString &sourceName, const QString &newName, const QString &description,
                        const std::function<void(int)> &onDone, const std::function<void(const QString &)> &onFail);

    EuclidBaseClient *m_base;
};
