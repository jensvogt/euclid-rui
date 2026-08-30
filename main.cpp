#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>

#include "AppSettings.h"
#include "client/EamClient.h"
#include "client/EkmClient.h"
#include "client/EmmClient.h"
#include "client/EmoClient.h"
#include "client/EnsClient.h"
#include "client/EqsClient.h"
#include "client/EsmClient.h"
#include "client/EuclidBaseClient.h"

int main(int argc, char *argv[]) {

    const QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName("Euclid");
    QGuiApplication::setApplicationName("Euclid RUI");

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
    EmoClient emoClient(&euclidClient);
    AppSettings appSettings;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("euclidClient", &euclidClient);
    engine.rootContext()->setContextProperty("eamClient", &eamClient);
    engine.rootContext()->setContextProperty("emmClient", &emmClient);
    engine.rootContext()->setContextProperty("eqsClient", &eqsClient);
    engine.rootContext()->setContextProperty("esmClient", &esmClient);
    engine.rootContext()->setContextProperty("ensClient", &ensClient);
    engine.rootContext()->setContextProperty("ekmClient", &ekmClient);
    engine.rootContext()->setContextProperty("emoClient", &emoClient);
    engine.rootContext()->setContextProperty("appSettings", &appSettings);
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
