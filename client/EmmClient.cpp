#include "EmmClient.h"
#include "EuclidBaseClient.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>

EmmClient::EmmClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EmmClient::fetchModuleStatus(const QString &moduleName) {
    m_base->post("emm", "list-modules", QJsonObject{}, true,
         [this, moduleName](const QJsonObject &response) {
             for (const QJsonArray modules = response.value("modules").toArray(); const auto &moduleValue : modules) {
                 const QJsonObject module = moduleValue.toObject();
                 if (module.value("name").toString().compare(moduleName, Qt::CaseInsensitive) != 0)
                     continue;

                 int runningInstances = 0;
                 QDateTime earliestStart;
                 for (const QJsonArray instances = module.value("instances").toArray(); const auto &instanceValue : instances) {
                     const QJsonObject instance = instanceValue.toObject();
                     if (instance.value("state").toString() != "RUNNING")
                         continue;
                     ++runningInstances;
                     if (const QDateTime created = QDateTime::fromString(instance.value("created").toString(), Qt::ISODateWithMs); created.isValid() && (!earliestStart.isValid() || created < earliestStart))
                         earliestStart = created;
                 }

                 const qint64 uptimeSeconds = earliestStart.isValid()
                     ? earliestStart.secsTo(QDateTime::currentDateTimeUtc())
                     : 0;
                 const int maxInstances = module.value("maxInstances").toInt(1);
                 emit moduleStatusLoaded(moduleName, uptimeSeconds, runningInstances, maxInstances);
                 return;
             }
             emit moduleStatusFailed(moduleName, "Module \"" + moduleName + "\" was not found.");
         },
         [this, moduleName](const QString &message) {
             emit moduleStatusFailed(moduleName, message);
         });
}
