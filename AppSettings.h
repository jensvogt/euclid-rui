#pragma once

#include <QObject>

// Per-(OS)-user app preferences, persisted via QSettings (an INI file under ~/.config on Linux,
// the registry on Windows, a plist on macOS - keyed by the organization/application name set in
// main.cpp). Currently just the auto-refresh interval every list/dashboard page polls on, but the
// natural place to add further user-configurable preferences later.
class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int autoRefreshSeconds READ autoRefreshSeconds WRITE setAutoRefreshSeconds NOTIFY autoRefreshSecondsChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    // 0 means auto-refresh is disabled; pages should stop their refresh timers in that case.
    [[nodiscard]]
    int autoRefreshSeconds() const { return m_autoRefreshSeconds; }
    Q_INVOKABLE void setAutoRefreshSeconds(int seconds);

signals:
    void autoRefreshSecondsChanged();

private:
    int m_autoRefreshSeconds;
};
