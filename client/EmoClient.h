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

    // Fetches up to `limit` historical samples for a metric name, oldest first, ready to plot
    // left-to-right. labelName/labelValue optionally filter to one label (e.g. labelName="method",
    // labelValue="GET"); leave both empty for a metric recorded without labels at all. Passing a
    // labelName with an empty labelValue does NOT make sense server-side (the "list" action
    // either filters on both or neither) - always pass both or neither.
    //
    // `resolution` picks which of emo's three storage tiers to read, i.e. how wide one point is:
    //   "RAW"  - one emo flush period (euclid.monitoring.average-period, 5 minutes by default),
    //            kept ~7 days
    //   "HOUR" - hourly buckets rolled up from RAW, kept ~90 days
    //   "DAY"  - daily buckets (UTC-aligned) rolled up from HOUR, kept ~5 years
    // Asking for a span longer than a tier's retention just returns the rows that still exist, so
    // callers should pick the tier that matches the span they want to show.
    Q_INVOKABLE void fetchSeries(const QString &metricName, const QString &labelName, const QString &labelValue,
                                 int limit = 50, const QString &resolution = QStringLiteral("RAW"));

    // Like fetchSeries(), but for a metric whose labels are too many (or too unpredictable) to plot
    // one line each - e.g. "eqs-service-time", labelled with all 22 EQS actions. Fetches every
    // label at once and folds the rows sharing a bucket into a single point, using the same rule
    // emo's own rollups use: a RATE ("...-service-count") is the total over its labels, a GAUGE
    // ("...-service-time") their sample-weighted mean. Result arrives on seriesLoaded() with an
    // empty labelValue.
    //
    // `limit` counts rows, not buckets, and one bucket costs one row *per label* - so it has to be
    // the number of buckets wanted times the number of labels expected. The server cuts
    // newest-first, so a cap that is too low shortens the history rather than corrupting it.
    Q_INVOKABLE void fetchAggregatedSeries(const QString &metricName, int limit = 500,
                                           const QString &resolution = QStringLiteral("RAW"));

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
