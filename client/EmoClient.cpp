#include "EmoClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonObject>

#include <map>

namespace {
// One bucket of a labelled metric is one row per label: eleven modules for the memory gauges,
// around twenty actions for a module's service counts. This is the cap on how many of those rows
// are asked for, and it only has to cover the newest bucket - the server cuts newest-first.
constexpr int kLabelFoldLimit = 128;
}

EmoClient::EmoClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EmoClient::fetchLatestMetric(const QString &metricName, const QString &moduleName, const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) const {
    QJsonObject body;
    body["name"] = metricName;
    body["labelName"] = "module";
    body["labelValue"] = moduleName;
    body["limit"] = 1;

    m_base->post("emo", "list", body, true,
         [onValue, onError](const QJsonObject &response) {
             const QJsonArray items = response.value("items").toArray();
             if (items.isEmpty()) {
                 onError("No data available yet");
                 return;
             }
             onValue(items.first().toObject().value("value").toDouble());
         },
         onError);
}

void EmoClient::fetchLatestMetric(const QString &metricName, const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) const {
    QJsonObject body;
    body["name"] = metricName;
    body["labelName"] = "host";
    body["labelValue"] = "vogje01-desktop";
    body["resolution"] = "RAW";
    body["limit"] = 1;

    m_base->post("emo", "list", body, true,
         [onValue, onError](const QJsonObject &response) {
             const QJsonArray items = response.value("items").toArray();
             if (items.isEmpty()) {
                 onError("No data available yet");
                 return;
             }
             onValue(items.first().toObject().value("value").toDouble());
         },
         onError);
}

void EmoClient::fetchLatestAvgMetric(const QString &metricName, const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) const {
    QJsonObject body;
    body["name"] = metricName;
    body["resolution"] = "RAW";
    // Enough rows to hold the newest bucket across every label the metric has. Asking for one row
    // was the bug this replaces: almost every metric here is labelled - memory usage per module,
    // service counts per action - so "the first row" was one arbitrary module's memory, or one
    // action's request count, reported as though it were the whole figure.
    body["limit"] = kLabelFoldLimit;

    m_base->post("emo", "list", body, true,
         [onValue, onError](const QJsonObject &response) {
             const QJsonArray items = response.value("items").toArray();
             if (items.isEmpty()) {
                 onError("No data available yet");
                 return;
             }

             // Rows come back newest-first, so the newest timestamp is the bucket to fold; the
             // ones behind it are older buckets of the same labels.
             QString newest;
             for (const QJsonValue &item: items) {
                 const auto timestamp = item.toObject().value("timestamp").toString();
                 if (timestamp > newest) newest = timestamp;
             }

             // The same rule emo's own rollups use, and fetchAggregatedSeries with them: a RATE is
             // the total over its labels - twenty actions' request counts add up to the module's -
             // while a GAUGE is their sample-weighted mean, since averaging percentages is what
             // makes them comparable.
             double total = 0;
             double weighted = 0;
             double samples = 0;
             long rows = 0;
             bool rate = false;
             for (const QJsonValue &item: items) {
                 const QJsonObject row = item.toObject();
                 if (row.value("timestamp").toString() != newest) continue;
                 const double value = row.value("value").toDouble();
                 const double rowSamples = row.value("samples").toDouble();
                 total += value;
                 weighted += value * rowSamples;
                 samples += rowSamples;
                 rate = row.value("type").toString() == QLatin1String("RATE");
                 ++rows;
             }

             if (rate) {
                 onValue(total);
                 return;
             }
             // Falls back to the plain mean when the rows carry no sample counts, which is still
             // the figure for the one-label case every gauge on the dashboard has.
             onValue(samples > 0 ? weighted / samples : (rows > 0 ? total / static_cast<double>(rows) : 0.0));
         },
         onError);
}

void EmoClient::fetchCpuUsage(const QString &moduleName) {
    fetchLatestMetric("euclid-cpu-usage", moduleName,
        [this, moduleName](const double percent) { emit cpuUsageLoaded(moduleName, percent); },
        [this, moduleName](const QString &message) { emit cpuUsageFailed(moduleName, message); });
}

void EmoClient::fetchMemoryUsage(const QString &moduleName) {
    fetchLatestMetric("euclid-memory-usage-percent", moduleName,
        [this, moduleName](const double percent) { emit memoryUsageLoaded(moduleName, percent); },
        [this, moduleName](const QString &message) { emit memoryUsageFailed(moduleName, message); });
}

void EmoClient::fetchAverage(const QString &metricName) {
    fetchLatestAvgMetric(metricName,
        [this, metricName](const double value) { emit averageLoaded(metricName, value); },
        [this, metricName](const QString &message) { emit averageFailed(metricName, message); });
}

void EmoClient::fetchSeries(const QString &metricName, const QString &labelName, const QString &labelValue, const int limit, const QString &resolution) {
    QJsonObject body;
    body["name"] = metricName;
    if (!labelName.isEmpty()) {
        body["labelName"] = labelName;
        body["labelValue"] = labelValue;
    }
    body["limit"] = limit;
    // Unknown values are ignored server-side, which falls back to the RAW tier - so a typo here
    // silently changes the point width rather than erroring. Pass one of RAW/HOUR/DAY.
    if (!resolution.isEmpty()) {
        body["resolution"] = resolution;
    }

    m_base->post("emo", "list", body, true,
         [this, metricName, labelValue](const QJsonObject &response) {
             QVariantList points;
             const QJsonArray items = response.value("items").toArray();
             // Server returns newest-first (sorted for the "most recent N" case); reverse to
             // chronological order for left-to-right plotting.
             for (auto it = items.constEnd(); it != items.constBegin();) {
                 --it;
                 const QJsonObject item = (*it).toObject();
                 QVariantMap point;
                 point["timestamp"] = item.value("timestamp").toString();
                 point["value"] = item.value("value").toDouble();
                 points << point;
             }
             emit seriesLoaded(metricName, labelValue, points);
         },
         [this, metricName, labelValue](const QString &message) { emit seriesFailed(metricName, labelValue, message); });
}

void EmoClient::fetchAggregatedSeries(const QString &metricName, const int limit, const QString &resolution) {
    QJsonObject body;
    body["name"] = metricName;
    body["limit"] = limit;
    if (!resolution.isEmpty()) {
        body["resolution"] = resolution;
    }

    m_base->post("emo", "list", body, true,
         [this, metricName, limit](const QJsonObject &response) {
             const QJsonArray items = response.value("items").toArray();

             // One bucket, across every label of the metric. Timestamps are fixed-width UTC
             // ISO8601 strings, so keying the map on them sorts the buckets chronologically
             // without parsing a single date.
             struct Bucket {
                 double total = 0;    // sum of the values, which is what a RATE aggregates to
                 double weighted = 0; // sum of value * samples, the numerator of a GAUGE's mean
                 double samples = 0;
                 bool rate = false;
             };
             std::map<QString, Bucket> buckets;

             for (const QJsonValue &item: items) {
                 const QJsonObject row = item.toObject();
                 const double value = row.value("value").toDouble();
                 const double samples = row.value("samples").toDouble();
                 Bucket &bucket = buckets[row.value("timestamp").toString()];
                 bucket.total += value;
                 bucket.weighted += value * samples;
                 bucket.samples += samples;
                 // Every row of one metric carries the same type, so last-write-wins is fine.
                 bucket.rate = row.value("type").toString() == QLatin1String("RATE");
             }

             // A response that hit the row cap was cut newest-first, which leaves its oldest
             // bucket holding only some of its labels - it would plot as a dip that never
             // happened, so drop it.
             if (items.size() >= limit && !buckets.empty()) {
                 buckets.erase(buckets.begin());
             }

             QVariantList points;
             for (const auto &[timestamp, bucket]: buckets) {
                 QVariantMap point;
                 point["timestamp"] = timestamp;
                 if (bucket.rate) {
                     point["value"] = bucket.total;
                 } else {
                     point["value"] = bucket.samples > 0 ? bucket.weighted / bucket.samples : 0.0;
                 }
                 points << point;
             }
             emit seriesLoaded(metricName, QString(), points);
         },
         [this, metricName](const QString &message) { emit seriesFailed(metricName, QString(), message); });
}
