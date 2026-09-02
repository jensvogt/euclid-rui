#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QJsonArray>
#include <QJsonObject>

class EuclidBaseClient;

// EKM (key management service) calls.
class EkmClient : public QObject {
    Q_OBJECT

public:
    explicit EkmClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    Q_INVOKABLE void fetchKeys(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                               const QString &sortColumn = QStringLiteral("name"),
                               const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void createKey(const QString &algorithm, int length = 128);
    Q_INVOKABLE void revokeKey(const QString &ern);
    // Schedules the key for permanent deletion after pendingWindowInDays (server default 7);
    // keyId is the key's name, i.e. what create-key/list-keys expose as "name" (not the ERN).
    Q_INVOKABLE void deleteKey(const QString &keyId, int pendingWindowInDays = 7);
    // Replaces the free text recorded with a key to say what it is for. An empty description is a
    // valid one and clears whatever the key carried; nothing else about the key is touched, which
    // is why this works on a revoked key or one scheduled for deletion too.
    Q_INVOKABLE void setKeyDescription(const QString &keyErn, const QString &description);
    // Upserts the tag unconditionally (no set-key-tag counterpart exists server-side).
    Q_INVOKABLE void addKeyTag(const QString &keyErn, const QString &key, const QString &value);
    // No-ops server-side if the key doesn't have this tag key.
    Q_INVOKABLE void deleteKeyTag(const QString &keyErn, const QString &key);

signals:
    void keysLoaded(const QVariantList &keys, int total);
    void keysFailed(const QString &message);
    void keysReload();
    void keyCreated(const QString &name);
    void keyCreateFailed(const QString &message);
    void keyDescriptionChanged(const QString &keyErn, const QString &description);
    void keyDescriptionFailed(const QString &message);
    void keyTagAdded(const QString &keyErn, const QString &key, const QString &value);
    void keyTagAddFailed(const QString &message);
    void keyTagDeleted(const QString &keyErn, const QString &key);
    void keyTagDeleteFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
