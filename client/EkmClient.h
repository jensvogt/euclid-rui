#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

class EuclidBaseClient;

// EKM (key management service) calls. Deliberately minimal: the server currently only supports
// creating and listing keys - no delete/purge/details/rotation actions exist yet.
class EkmClient : public QObject {
    Q_OBJECT

public:
    explicit EkmClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    Q_INVOKABLE void fetchKeys(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                               const QString &sortColumn = QStringLiteral("name"),
                               const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void createKey(const QString &algorithm, int length = 128);

signals:
    void keysLoaded(const QVariantList &keys, int total);
    void keysFailed(const QString &message);
    void keysReload();
    void keyCreated(const QString &name);
    void keyCreateFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
