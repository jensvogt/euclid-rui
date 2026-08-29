#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#include "AppSettings.h"
#include "client/EmmClient.h"
#include "client/EmoClient.h"
#include "client/EnsClient.h"
#include "client/EqsClient.h"
#include "client/EsmClient.h"
#include "client/EuclidBaseClient.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
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
    EmmClient emmClient(&euclidClient);
    EqsClient eqsClient(&euclidClient);
    EsmClient esmClient(&euclidClient);
    EnsClient ensClient(&euclidClient);
    EmoClient emoClient(&euclidClient);
    AppSettings appSettings;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("euclidClient", &euclidClient);
    engine.rootContext()->setContextProperty("emmClient", &emmClient);
    engine.rootContext()->setContextProperty("eqsClient", &eqsClient);
    engine.rootContext()->setContextProperty("esmClient", &esmClient);
    engine.rootContext()->setContextProperty("ensClient", &ensClient);
    engine.rootContext()->setContextProperty("emoClient", &emoClient);
    engine.rootContext()->setContextProperty("appSettings", &appSettings);
    engine.rootContext()->setContextProperty("cliUser", parser.value(userOption));
    engine.rootContext()->setContextProperty("cliPassword", parser.value(passwordOption));
    engine.rootContext()->setContextProperty("cliNamespace", parser.value(namespaceOption));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, [] { QGuiApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.load(QUrl(QStringLiteral("qrc:/EuclidRui/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    return QGuiApplication::exec();
}
