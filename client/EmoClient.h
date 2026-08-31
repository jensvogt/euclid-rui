#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
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

    Q_INVOKABLE void fetchAverage(const QString &metricName);

    // Fetches up to `limit` raw historical samples for a metric name - one point per emo flush
    // period (5 minutes by default server-side), oldest first, ready to plot left-to-right.
    // labelName/labelValue optionally filter to one label (e.g. labelName="method",
    // labelValue="GET"); leave both empty for a metric recorded without labels at all. Passing a
    // labelName with an empty labelValue does NOT make sense server-side (the "list" action
    // either filters on both or neither) - always pass both or neither.
    Q_INVOKABLE void fetchSeries(const QString &metricName, const QString &labelName, const QString &labelValue, int limit = 50);

signals:
    void cpuUsageLoaded(const QString &moduleName, double percent);
    void cpuUsageFailed(const QString &moduleName, const QString &message);
    void memoryUsageLoaded(const QString &moduleName, double percent);
    void memoryUsageFailed(const QString &moduleName, const QString &message);
    void averageLoaded(const QString &moduleName, double value);
    void averageFailed(const QString &moduleName, const QString &value);
    // Each point is a QVariantMap{"timestamp": ISO8601 string, "value": double}. labelValue
    // echoes back whatever was passed to fetchSeries (empty if none), so callers issuing several
    // fetchSeries() calls for the same metricName under different labels (e.g. one per HTTP
    // method) can tell the responses apart.
    void seriesLoaded(const QString &metricName, const QString &labelValue, const QVariantList &points);
    void seriesFailed(const QString &metricName, const QString &labelValue, const QString &message);

private:
    void fetchLatestMetric(const QString &metricName, const QString &moduleName,
                            const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) const;

    void fetchLatestAvgMetric(const QString &metricName, const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) const;

    EuclidBaseClient *m_base;
};
