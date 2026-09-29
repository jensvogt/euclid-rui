#pragma once

#include <QJsonObject>
#include <QJsonValue>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// One message attribute map - a sender's own attributes or euclid's system ones - as the list a QML
// Repeater can walk.
//
// Shared between EQS and ENS rather than copied into each, because the shape is shared on the other
// side too: both modules store attributes as Dto::COM::Variant, so there is one encoding to read
// and it should have one reader.
//
// A list rather than the map it arrives as, because the order matters to a reader and a QML map has
// none to offer: QJsonObject keeps its keys sorted, so walking it here is what puts the attributes
// on screen in the same order every time rather than in whatever order the object happened to be
// built in.
//
// Each value carries its own type - Variant writes {"type": ..., "value": ...} so that an attribute
// sent as a long does not come back as a double. The type decides how the value is rendered here
// for the same reason: QJsonValue::toDouble() on a long turns 10000000000 into 1e+10, which is not
// what anybody put in.
inline QVariantList attributesToList(const QJsonObject &attributes) {

    QVariantList entries;
    for (auto it = attributes.begin(); it != attributes.end(); ++it) {

        const QJsonObject variant = it.value().toObject();
        const QString type = variant.value("type").toString();
        const QJsonValue value = variant.value("value");

        QString text;
        if (type == QLatin1String("int") || type == QLatin1String("long"))
            text = QString::number(value.toInteger());
        else if (type == QLatin1String("double") || type == QLatin1String("float"))
            text = QString::number(value.toDouble());
        else if (type == QLatin1String("bool"))
            text = value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
        else
            // Strings, and binary - which arrives base64 encoded and is shown as it arrived.
            // Decoding it would produce bytes that are not text, which is the one thing a value
            // column cannot display; the type beside it is what says the base64 is the encoding
            // and not the value.
            text = value.toString();

        QVariantMap entry;
        entry["name"] = it.key();
        entry["type"] = type;
        entry["value"] = text;
        entries << entry;
    }
    return entries;
}
