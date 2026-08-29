#include "AppSettings.h"

#include <QSettings>
#include <algorithm>

namespace {
constexpr int kDefaultAutoRefreshSeconds = 10;
constexpr auto kAutoRefreshSecondsKey = "autoRefreshSeconds";
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      m_autoRefreshSeconds(QSettings().value(kAutoRefreshSecondsKey, kDefaultAutoRefreshSeconds).toInt()) {
}

void AppSettings::setAutoRefreshSeconds(const int seconds) {
    const int clamped = std::max(0, seconds);
    if (m_autoRefreshSeconds == clamped)
        return;
    m_autoRefreshSeconds = clamped;
    QSettings().setValue(kAutoRefreshSecondsKey, m_autoRefreshSeconds);
    emit autoRefreshSecondsChanged();
}
