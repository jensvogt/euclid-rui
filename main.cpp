#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QQuickWindow>

#include "AppSettings.h"
#include "client/EamClient.h"
#include "client/EapClient.h"
#include "client/EkmClient.h"
#include "client/EmmClient.h"
#include "client/EmoClient.h"
#include "client/EnsClient.h"
#include "client/EqsClient.h"
#include "client/EsmClient.h"
#include "client/EtsClient.h"
#include "client/EuclidBaseClient.h"
#include "client/EventStreamClient.h"

int main(int argc, char *argv[]) {

    const QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName("Euclid");
    QGuiApplication::setApplicationName("Euclid RUI");
    QGuiApplication::setApplicationVersion(QStringLiteral(APP_VERSION));
    // Taskbar, window manager and (on Windows) the title bar. The coloured variant is the one Qt
    // can draw: the mono and small SVGs are stroked with "currentColor", which is a CSS notion
    // Qt's SVG renderer has no value for.
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/EuclidRui/dist/branding/euclid-icon.svg")));

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
    EnsClient ensClient(&euclidClient);
    EkmClient ekmClient(&euclidClient);
    EapClient eapClient(&euclidClient);
    EtsClient etsClient(&euclidClient);
    EmoClient emoClient(&euclidClient);
    EventStreamClient eventStream(&euclidClient);
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

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("euclidClient", &euclidClient);
    engine.rootContext()->setContextProperty("eamClient", &eamClient);
    engine.rootContext()->setContextProperty("emmClient", &emmClient);
    engine.rootContext()->setContextProperty("eqsClient", &eqsClient);
    engine.rootContext()->setContextProperty("esmClient", &esmClient);
    engine.rootContext()->setContextProperty("ensClient", &ensClient);
    engine.rootContext()->setContextProperty("ekmClient", &ekmClient);
    engine.rootContext()->setContextProperty("eapClient", &eapClient);
    engine.rootContext()->setContextProperty("etsClient", &etsClient);
    engine.rootContext()->setContextProperty("emoClient", &emoClient);
    engine.rootContext()->setContextProperty("eventStream", &eventStream);

    // Best-effort: the unsubscribe is a network call and the process may not live long enough to
    // send it, which is why the subscription is registered as ephemeral - a gateway restart clears
    // whatever was left behind.
    QObject::connect(&app, &QGuiApplication::aboutToQuit, &eventStream, &EventStreamClient::stop);
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
