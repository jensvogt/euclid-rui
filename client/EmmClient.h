#pragma once

#include <QObject>
#include <QString>

class EuclidBaseClient;

// EMM (module manager) calls: live status of the euclid-mgr-supervised
// module processes (instance counts, uptime, autoscaling capacity).
class EmmClient : public QObject {
    Q_OBJECT

public:
    explicit EmmClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    Q_INVOKABLE void fetchModuleStatus(const QString &moduleName);

signals:
    void moduleStatusLoaded(const QString &moduleName, qint64 uptimeSeconds, int runningInstances, int maxInstances);
    void moduleStatusFailed(const QString &moduleName, const QString &message);

private:
    EuclidBaseClient *m_base;
};
