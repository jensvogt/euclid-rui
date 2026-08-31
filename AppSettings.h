#pragma once

#include <QObject>
#include <QString>

// Per-(OS)-user app preferences, persisted as JSON at $HOME/.euclid/rui.json - the same dot
// directory the euclid CLI keeps its own JSON state in ($HOME/.euclid/credentials), so a machine
// has one obvious place holding everything euclid client-side. Chosen over QSettings (which this
// used to be, and which still gets read once to migrate an existing install) because a plain,
// indented JSON file in the home directory can be read, edited, diffed and copied to another
// machine, which an INI under ~/.config - or the Windows registry - cannot.
//
// Holds the auto-refresh interval every list/dashboard page polls on, and the euclid gateway this
// session talks to, and is the natural place to add further user-configurable preferences later.
class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(int autoRefreshSeconds READ autoRefreshSeconds WRITE setAutoRefreshSeconds NOTIFY autoRefreshSecondsChanged)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY baseUrlChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY baseUrlChanged)
    Q_PROPERTY(bool useTls READ useTls WRITE setUseTls NOTIFY baseUrlChanged)
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString configFilePath READ configFilePath CONSTANT)

public:
    explicit AppSettings(QObject *parent = nullptr);

    // 0 means auto-refresh is disabled; pages should stop their refresh timers in that case.
    [[nodiscard]]
    int autoRefreshSeconds() const { return m_autoRefreshSeconds; }
    Q_INVOKABLE void setAutoRefreshSeconds(int seconds);

    // Host and port of the euclid-mgr gateway - "localhost:5566" for a local backend, anything
    // reachable for a remote one. Empty hosts and out-of-range ports are ignored rather than
    // stored, since an unusable gateway address would leave no way back in through the UI.
    [[nodiscard]]
    QString host() const { return m_host; }
    Q_INVOKABLE void setHost(const QString &host);

    [[nodiscard]]
    int port() const { return m_port; }
    Q_INVOKABLE void setPort(int port);

    // The gateway only speaks TLS when euclid.gateway.tls.enabled is set server-side (it defaults
    // to off there), so which scheme to use is a property of the deployment being connected to,
    // not something the client can assume. Defaults to https, matching the dev backend.
    [[nodiscard]]
    bool useTls() const { return m_useTls; }
    Q_INVOKABLE void setUseTls(bool useTls);

    // "<scheme>://<host>:<port>/" - what EuclidBaseClient posts every request to.
    [[nodiscard]]
    QString baseUrl() const;

    // Absolute path of the JSON file above, e.g. "/home/alice/.euclid/rui.json". Shown in the
    // settings page so the file this writes is findable without guessing.
    [[nodiscard]]
    static QString configFilePath();

signals:
    void autoRefreshSecondsChanged();
    // One signal for host/port/useTls: they only matter as the URL they compose into, and every
    // consumer cares about that rather than the individual parts.
    void baseUrlChanged();

private:
    // Reads configFilePath() into the members, leaving anything absent or unusable at its default.
    void load();

    // Writes every current value back out. Called from each setter - the file is a few hundred
    // bytes and settings change at human speed, so there is nothing to gain from batching.
    void save() const;

    int m_autoRefreshSeconds;
    QString m_host;
    int m_port;
    bool m_useTls;
};
