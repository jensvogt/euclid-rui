#include "EadClient.h"
#include "EuclidBaseClient.h"

#include <QJsonArray>

namespace {

// One "list-events" entry as the pages read it. "module" and "namespace" are kept under the names
// EAD answers with rather than being renamed to match the C++ entity behind them (moduleName,
// nameSpace): what a page shows is the wire field, and one spelling is enough.
QVariantMap eventToMap(const QJsonObject &event) {
    QVariantMap entry;
    entry["accountId"] = event.value("accountId").toString();
    entry["namespace"] = event.value("namespace").toString();
    entry["userId"] = event.value("userId").toString();
    entry["module"] = event.value("module").toString();
    entry["command"] = event.value("command").toString();
    // The request body as it was sent, with anything under a sensitive field name already replaced
    // server-side. Shown as stored - it is a record, not something to reformat.
    entry["parameters"] = event.value("parameters").toString();
    // The HTTP status the command was answered with. The reason a refusal is in the trail at all,
    // so it is what the display colours on.
    entry["status"] = event.value("status").toInt();
    entry["created"] = event.value("created").toString();
    return entry;
}

}// namespace

EadClient::EadClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EadClient::fetchEvents(const QString &userId, const QString &moduleName, const QString &command,
                            const int pageIndex, const int pageSize) {
    QJsonObject body;
    body["userId"] = userId;
    body["module"] = moduleName;
    body["command"] = command;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;

    m_base->post("ead", "list-events", body, true,
         [this](const QJsonObject &response) {
             QVariantList events;
             for (const QJsonArray array = response.value("events").toArray(); const auto &value: array)
                 events << eventToMap(value.toObject());
             emit eventsLoaded(events, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit eventsFailed(message);
         });
}
