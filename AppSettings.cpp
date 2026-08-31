#include "AppSettings.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSettings>
#include <algorithm>

namespace {
constexpr int kDefaultAutoRefreshSeconds = 10;
constexpr auto kDefaultHost = "localhost";
constexpr int kDefaultPort = 5566;
constexpr bool kDefaultUseTls = true;

// JSON keys. The gateway settings are nested because they are only meaningful together.
constexpr auto kAutoRefreshSecondsKey = "autoRefreshSeconds";
constexpr auto kGatewayKey = "gateway";
constexpr auto kHostKey = "host";
constexpr auto kPortKey = "port";
constexpr auto kUseTlsKey = "useTls";

bool isValidPort(const int port) { return port > 0 && port <= 65535; }
}

QString AppSettings::configFilePath() {
    return QDir::homePath() + QStringLiteral("/.euclid/rui.json");
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      // Defaults first; load() overwrites whatever the file actually specifies. Reading QSettings
      // for the starting values migrates an install from back when this class was QSettings-based
      // - once rui.json exists it wins, and the old INI/registry entry is simply left behind.
      m_autoRefreshSeconds(QSettings().value(kAutoRefreshSecondsKey, kDefaultAutoRefreshSeconds).toInt()),
      m_host(kDefaultHost),
      m_port(kDefaultPort),
      m_useTls(kDefaultUseTls) {

    load();

    // Sanity-check whatever came out of the file or the old settings: it can be nonsense if the
    // JSON was hand-edited, and starting up pointing at an address no request can reach would
    // leave no way to fix it from the UI.
    m_autoRefreshSeconds = std::max(0, m_autoRefreshSeconds);
    if (m_host.isEmpty())
        m_host = kDefaultHost;
    if (!isValidPort(m_port))
        m_port = kDefaultPort;

    // Write the file out on first run, so it exists to be found and edited before anything in the
    // UI has been changed.
    if (!QFile::exists(configFilePath()))
        save();
}

void AppSettings::load() {

    QFile file(configFilePath());
    if (!file.exists())
        return;
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning("AppSettings: cannot read %s: %s", qUtf8Printable(configFilePath()), qUtf8Printable(file.errorString()));
        return;
    }

    QJsonParseError error{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        // Keep the defaults and leave the file alone rather than overwriting what the user was in
        // the middle of hand-editing - the next setter call will rewrite it anyway.
        qWarning("AppSettings: ignoring malformed %s: %s", qUtf8Printable(configFilePath()), qUtf8Printable(error.errorString()));
        return;
    }

    const QJsonObject root = document.object();
    if (const QJsonValue value = root.value(kAutoRefreshSecondsKey); value.isDouble())
        m_autoRefreshSeconds = value.toInt();

    const QJsonObject gateway = root.value(kGatewayKey).toObject();
    if (const QJsonValue value = gateway.value(kHostKey); value.isString())
        m_host = value.toString().trimmed();
    if (const QJsonValue value = gateway.value(kPortKey); value.isDouble())
        m_port = value.toInt();
    if (const QJsonValue value = gateway.value(kUseTlsKey); value.isBool())
        m_useTls = value.toBool();
}

void AppSettings::save() const {

    const QString path = configFilePath();
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        qWarning("AppSettings: cannot create directory for %s", qUtf8Printable(path));
        return;
    }

    QJsonObject gateway;
    gateway[kHostKey] = m_host;
    gateway[kPortKey] = m_port;
    gateway[kUseTlsKey] = m_useTls;

    QJsonObject root;
    root[kAutoRefreshSecondsKey] = m_autoRefreshSeconds;
    root[kGatewayKey] = gateway;

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning("AppSettings: cannot write %s: %s", qUtf8Printable(path), qUtf8Printable(file.errorString()));
        return;
    }
    // Indented, not compact: the whole point of putting this in the home directory rather than in
    // ~/.config is that it can be opened and edited by hand.
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

void AppSettings::setAutoRefreshSeconds(const int seconds) {
    const int clamped = std::max(0, seconds);
    if (m_autoRefreshSeconds == clamped)
        return;
    m_autoRefreshSeconds = clamped;
    save();
    emit autoRefreshSecondsChanged();
}

void AppSettings::setHost(const QString &host) {
    const QString trimmed = host.trimmed();
    if (trimmed.isEmpty() || trimmed == m_host)
        return;
    m_host = trimmed;
    save();
    emit baseUrlChanged();
}

void AppSettings::setPort(const int port) {
    if (!isValidPort(port) || port == m_port)
        return;
    m_port = port;
    save();
    emit baseUrlChanged();
}

void AppSettings::setUseTls(const bool useTls) {
    if (useTls == m_useTls)
        return;
    m_useTls = useTls;
    save();
    emit baseUrlChanged();
}

QString AppSettings::baseUrl() const {
    return QStringLiteral("%1://%2:%3/").arg(m_useTls ? QStringLiteral("https") : QStringLiteral("http"), m_host, QString::number(m_port));
}
