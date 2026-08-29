#pragma once

#include <QObject>
#include <QString>
#include <functional>

class EuclidBaseClient;

// EMO (monitoring) calls: queries metrics recorded by other modules, e.g. per-module CPU usage.
class EmoClient : public QObject {
    Q_OBJECT

public:
    explicit EmoClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    // Fetches the most recent "euclid-cpu-usage" reading for the given module (e.g. "eqs").
    Q_INVOKABLE void fetchCpuUsage(const QString &moduleName);

    // Fetches the most recent "euclid-memory-usage-percent" reading for the given module.
    Q_INVOKABLE void fetchMemoryUsage(const QString &moduleName);

signals:
    void cpuUsageLoaded(const QString &moduleName, double percent);
    void cpuUsageFailed(const QString &moduleName, const QString &message);
    void memoryUsageLoaded(const QString &moduleName, double percent);
    void memoryUsageFailed(const QString &moduleName, const QString &message);

private:
    void fetchLatestMetric(const QString &metricName, const QString &moduleName,
                            const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError);

    EuclidBaseClient *m_base;
};
