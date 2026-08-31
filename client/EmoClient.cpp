#include "EmoClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonObject>

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

void EmoClient::fetchLatestAvgMetric(const QString &metricName, const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) const {
    QJsonObject body;
    body["name"] = metricName;

    m_base->post("emo", "average", body, true,
         [onValue, onError](const QJsonObject &response) {
             onValue(response["average"].toDouble());
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

void EmoClient::fetchSeries(const QString &metricName, const QString &labelName, const QString &labelValue, const int limit) {
    QJsonObject body;
    body["name"] = metricName;
    if (!labelName.isEmpty()) {
        body["labelName"] = labelName;
        body["labelValue"] = labelValue;
    }
    body["limit"] = limit;

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
