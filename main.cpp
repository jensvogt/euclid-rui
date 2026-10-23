#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QLibrary>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QQuickWindow>

#include "AppSettings.h"
#include "client/EadClient.h"
#include "client/EamClient.h"
#include "client/EagClient.h"
#include "client/EapClient.h"
#include "client/EkmClient.h"
#include "client/EkvClient.h"
#include "client/EmmClient.h"
#include "client/EmoClient.h"
#include "client/EnsClient.h"
#include "client/EqsClient.h"
#include "client/EsmClient.h"
#include "client/EssClient.h"
#include "client/EtsClient.h"
#include "client/EuclidBaseClient.h"

namespace {

    /**
     * @brief Settles the size of the cursors this application loads, before Qt loads any.
     *
     * @par
     * Qt's X11 plugin loads cursor images through xcb-util-cursor, which decides how big they
     * should be from, in order: the XCURSOR_SIZE environment variable, the X resource
     * "Xcursor.size", "Xft.dpi" - and, when none of those answers, one forty-eighth of the smaller
     * dimension of the X screen. That last rule is a guess from a time when one X screen meant one
     * monitor. A workstation whose screen spans five of them and stands 2160 tall makes it 45, and
     * the nearest cursor a theme ships is 48: twice the size of every other cursor on the desktop.
     *
     * @par
     * Which is seen, oddly, as a huge crosshair over the charts and a huge hand over anything
     * clickable, while the ordinary arrow stays the right size - because a cursor this application
     * never sets is not one it loaded. That one belongs to the compositor and was never in doubt.
     *
     * @par
     * The context those cursors come from is built once, while the platform plugin starts, and is
     * not revisited. So the answer is settled here rather than left to whether the resource
     * database can be read at that instant, and taken from where the desktop keeps it. An
     * XCURSOR_SIZE already in the environment is left alone: somebody who sets it means it.
     */
    void settleCursorSize() {

        if (qEnvironmentVariableIsSet("XCURSOR_SIZE")) return;

        // Nothing to read and nothing to fix without an X server - a Wayland client is told its
        // cursor size by the compositor, and there is no XCURSOR_SIZE in that conversation.
        if (!qEnvironmentVariableIsSet("DISPLAY")) return;

        // Resolved rather than linked: this is one lookup on one platform, and libX11 is already
        // in the process on any desktop that has an X server to ask. If it is not, the default
        // below is still better than a number worked out from how many monitors are plugged in.
        QLibrary x11(QStringLiteral("X11"), 6);
        const auto openDisplay = reinterpret_cast<void *(*) (const char *)>(x11.resolve("XOpenDisplay"));
        const auto resourceString = reinterpret_cast<char *(*) (void *)>(x11.resolve("XResourceManagerString"));
        const auto closeDisplay = reinterpret_cast<int (*)(void *)>(x11.resolve("XCloseDisplay"));

        int size = 0;
        if (openDisplay && resourceString && closeDisplay) {
            if (void *display = openDisplay(nullptr)) {
                if (const char *resources = resourceString(display)) {
                    // The same two resources xcb-util-cursor reads, in the same order, so this
                    // agrees with it whenever it had an answer of its own.
                    for (const QByteArray &line: QByteArray(resources).split('\n')) {
                        const int colon = line.indexOf(':');
                        if (colon < 0) continue;
                        const QByteArray key = line.left(colon).trimmed();
                        const QByteArray value = line.mid(colon + 1).trimmed();
                        if (key == "Xcursor.size") {
                            size = value.toInt();
                            break;
                        }
                        // Not a cursor size but the size of everything else, which is what a
                        // desktop that states neither has been scaled by. 16 points at 72 to
                        // the inch is the cursor the specification describes.
                        if (key == "Xft.dpi" && size == 0) {
                            size = value.toInt() * 16 / 72;
                        }
                    }
                }
                closeDisplay(display);
            }
        }

        // What an X11 desktop has meant by a cursor for as long as there have been cursor themes,
        // and what GNOME, KDE and the themes themselves still ship as their first size.
        if (size <= 0) size = 24;

        qputenv("XCURSOR_SIZE", QByteArray::number(size));
    }

}// namespace

int main(int argc, char *argv[]) {

    // Before the QGuiApplication, deliberately: constructing it starts the platform plugin, and
    // the plugin builds the cursor context on the way up.
    settleCursorSize();

    const QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName("Euclid");
    QGuiApplication::setApplicationName("Euclid RUI");
    QGuiApplication::setApplicationVersion(QStringLiteral(APP_VERSION));
    // Taskbar, window manager and (on Windows) the title bar. The coloured variant is the one Qt
    // can draw: the mono and small SVGs are stroked with "currentColor", which is a CSS notion
    // Qt's SVG renderer has no value for.
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/EuclidRui/dist/branding/euclid-icon.svg")));
    // Ties a running window to dist/linux/euclid-rui.desktop, which is what a Linux desktop reads
    // the launcher icon and name from - the window icon above is only what Qt draws itself. Without
    // it the match is left to guesswork: on X11 Qt would fall back to the executable's name, and on
    // Wayland, where there is no WM_CLASS to guess from, the window would go unmatched entirely and
    // show the fallback icon. Ignored on Windows and macOS, which have their own mechanisms.
    QGuiApplication::setDesktopFileName(QStringLiteral("euclid-rui"));

    QCommandLineParser parser;
    parser.setApplicationDescription("Euclid RUI - Qt6/QML dashboard for the euclid backend");
    parser.addHelpOption();
    const QCommandLineOption userOption(QStringList{"user", "u"}, "Username or email to sign in with, skipping the login dialog.", "user");
    const QCommandLineOption passwordOption(QStringList{"password", "p"}, "Password to sign in with.", "password");
    const QCommandLineOption namespaceOption(QStringList{"namespace", "n"}, "Namespace to select after signing in; defaults to the first available.", "namespace");
    parser.addOption(userOption);
    parser.addOption(passwordOption);
    parser.addOption(namespaceOption);
    parser.process(app);

    QQuickStyle::setStyle("Material");

    EuclidBaseClient euclidClient;
    EamClient eamClient(&euclidClient);
    EmmClient emmClient(&euclidClient);
    EqsClient eqsClient(&euclidClient);
    EsmClient esmClient(&euclidClient);
    EssClient essClient(&euclidClient);
    EnsClient ensClient(&euclidClient);
    EkmClient ekmClient(&euclidClient);
    EkvClient ekvClient(&euclidClient);
    EapClient eapClient(&euclidClient);
    EtsClient etsClient(&euclidClient);
    EagClient eagClient(&euclidClient);
    EmoClient emoClient(&euclidClient);
    EadClient eadClient(&euclidClient);
    AppSettings appSettings;

    // The gateway address lives in AppSettings (which persists it) and is pushed into the client,
    // so the client needs no settings dependency of its own. The login dialog edits the settings;
    // this connection is what makes the next request actually go somewhere else.
    euclidClient.setBaseUrl(appSettings.baseUrl());
    QObject::connect(&appSettings, &AppSettings::baseUrlChanged, &euclidClient,
                     [&appSettings, &euclidClient] { euclidClient.setBaseUrl(appSettings.baseUrl()); });

    // Same arrangement for how requests authenticate: the setting is the source of truth, the
    // client is told about it, and neither knows about the other's storage.
    const auto applyCredentials = [&appSettings, &euclidClient] {
        euclidClient.setAuthMode(appSettings.authMode());
        euclidClient.setAccessKey(appSettings.accessKeyId(), appSettings.secretAccessKey());
    };
    applyCredentials();
    QObject::connect(&appSettings, &AppSettings::credentialsChanged, &euclidClient, applyCredentials);

    // And the other direction, for the one value the gateway issues rather than the operator: the
    // access key that comes back on login. Stored so the settings page shows the key that is
    // actually in use, and so the next start signs with it before anyone has logged in - without
    // this, a RUI pointed at a second installation goes on holding the first one's key, and every
    // request after a successful login is refused for a signature that cannot match.
    QObject::connect(&euclidClient, &EuclidBaseClient::accessKeyIssued, &appSettings,
                     [&appSettings](const QString &accessKeyId, const QString &secretAccessKey) {
                         if (appSettings.accessKeyId() == accessKeyId && appSettings.secretAccessKey() == secretAccessKey)
                             return;
                         appSettings.setAccessKeyId(accessKeyId);
                         appSettings.setSecretAccessKey(secretAccessKey);
                     });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("euclidClient", &euclidClient);
    engine.rootContext()->setContextProperty("eamClient", &eamClient);
    engine.rootContext()->setContextProperty("emmClient", &emmClient);
    engine.rootContext()->setContextProperty("eqsClient", &eqsClient);
    engine.rootContext()->setContextProperty("esmClient", &esmClient);
    engine.rootContext()->setContextProperty("essClient", &essClient);
    engine.rootContext()->setContextProperty("ensClient", &ensClient);
    engine.rootContext()->setContextProperty("ekmClient", &ekmClient);
    engine.rootContext()->setContextProperty("ekvClient", &ekvClient);
    engine.rootContext()->setContextProperty("eapClient", &eapClient);
    engine.rootContext()->setContextProperty("etsClient", &etsClient);
    engine.rootContext()->setContextProperty("eagClient", &eagClient);
    engine.rootContext()->setContextProperty("emoClient", &emoClient);
    engine.rootContext()->setContextProperty("eadClient", &eadClient);

    engine.rootContext()->setContextProperty("appSettings", &appSettings);
    // QML has no way to read QCoreApplication::applicationVersion() on its own, nor the Qt
    // version it is running on; the about box shows both.
    engine.rootContext()->setContextProperty("appVersion", QGuiApplication::applicationVersion());
    engine.rootContext()->setContextProperty("qtVersion", QStringLiteral(QT_VERSION_STR));
    engine.rootContext()->setContextProperty("buildDate", QStringLiteral(BUILD_DATE));
    engine.rootContext()->setContextProperty("cliUser", parser.value(userOption));
    engine.rootContext()->setContextProperty("cliPassword", parser.value(passwordOption));
    engine.rootContext()->setContextProperty("cliNamespace", parser.value(namespaceOption));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QGuiApplication::exit(-1); }, Qt::QueuedConnection);

    engine.load(QUrl(QStringLiteral("qrc:/EuclidRui/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    // Get the first root window
    if (auto *window = qobject_cast<QQuickWindow*>(engine.rootObjects().first())) {
        // Force assignment to the primary screen
        QScreen *primaryScreen = QGuiApplication::primaryScreen();
        window->setScreen(primaryScreen);

        // Optional: Recenter on the primary screen's available geometry
        const QRect screenGeometry = primaryScreen->availableGeometry();
        const int x = screenGeometry.x() + (screenGeometry.width() - window->width()) / 2;
        const int y = screenGeometry.y() + (screenGeometry.height() - window->height()) / 2;
        window->setPosition(x, y);
    }

    return QGuiApplication::exec();
}
