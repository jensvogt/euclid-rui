#include "EmoClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>
#include <QJsonObject>

EmoClient::EmoClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EmoClient::fetchLatestMetric(const QString &metricName, const QString &moduleName,
                                   const std::function<void(double)> &onValue, const std::function<void(const QString &)> &onError) {
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
