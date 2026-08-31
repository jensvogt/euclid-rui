#include "RequestSigner.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QMessageAuthenticationCode>

namespace {

QByteArray hmacSha256(const QByteArray &key, const QByteArray &data) {
    QMessageAuthenticationCode code(QCryptographicHash::Sha256, key);
    code.addData(data);
    return code.result();
}

QString sha256Hex(const QByteArray &data) {
    return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
}

QString headerOrEmpty(const QMap<QString, QString> &headers, const QString &name) {
    return headers.value(name, QString());
}

}// namespace

QStringList RequestSigner::sigV4SignedHeaders() {
    return {"host", "x-amz-content-sha256", "x-amz-date",
            "x-euclid-account-id", "x-euclid-action", "x-euclid-region", "x-euclid-target", "x-euclid-user-id"};
}

QStringList RequestSigner::rfc9421Components() {
    return {"@method", "@path", "@authority", "content-digest",
            "x-euclid-account-id", "x-euclid-action", "x-euclid-region", "x-euclid-target", "x-euclid-user-id"};
}

QMap<QString, QString> RequestSigner::signSigV4(const Request &request, const Credentials &credentials) {

    // UTC, and both forms of it: the long one goes in x-amz-date and the string-to-sign, the
    // short one into the credential scope and the key derivation. The server checks they agree.
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const QString amzDate = now.toString(QStringLiteral("yyyyMMdd'T'HHmmss'Z'"));
    const QString dateStamp = now.toString(QStringLiteral("yyyyMMdd"));
    const QString payloadHash = sha256Hex(request.body);

    // The signature covers these two, so they have to be in the map the canonical request is
    // built from - not just on the wire afterwards.
    QMap<QString, QString> headers = request.headers;
    headers["host"] = request.authority;
    headers["x-amz-date"] = amzDate;
    headers["x-amz-content-sha256"] = payloadHash;

    const QStringList signedHeaders = sigV4SignedHeaders();
    QString canonicalHeaders;
    for (const QString &name: signedHeaders)
        canonicalHeaders += name + ":" + headerOrEmpty(headers, name) + "\n";

    const QString signedHeaderList = signedHeaders.join(QLatin1Char(';'));

    // METHOD \n path \n query \n canonical-headers \n (blank) signed-headers \n payload-hash.
    // canonicalHeaders already ends in a newline, which is what produces the blank line SigV4
    // requires between the headers and the signed-header list.
    const QString canonicalRequest = request.method + "\n" + request.path + "\n" + QString()
                                     + "\n" + canonicalHeaders + "\n" + signedHeaderList + "\n" + payloadHash;

    const QString credentialScope = dateStamp + "/" + credentials.region + "/" + credentials.service + "/aws4_request";
    const QString stringToSign = QStringLiteral("AWS4-HMAC-SHA256\n") + amzDate + "\n" + credentialScope
                                 + "\n" + sha256Hex(canonicalRequest.toUtf8());

    // kDate -> kRegion -> kService -> kSigning, each HMAC keyed by the previous step.
    const QByteArray kDate = hmacSha256(("AWS4" + credentials.secretAccessKey).toUtf8(), dateStamp.toUtf8());
    const QByteArray kRegion = hmacSha256(kDate, credentials.region.toUtf8());
    const QByteArray kService = hmacSha256(kRegion, credentials.service.toUtf8());
    const QByteArray signingKey = hmacSha256(kService, QByteArrayLiteral("aws4_request"));
    const QString signature = QString::fromLatin1(hmacSha256(signingKey, stringToSign.toUtf8()).toHex());

    return {
            {"x-amz-date", amzDate},
            {"x-amz-content-sha256", payloadHash},
            {"Authorization", "AWS4-HMAC-SHA256 Credential=" + credentials.accessKeyId + "/" + credentialScope
                                      + ", SignedHeaders=" + signedHeaderList + ", Signature=" + signature},
    };
}

QMap<QString, QString> RequestSigner::signRfc9421(const Request &request, const Credentials &credentials) {

    // RFC 9530: the body is bound in through Content-Digest, which is itself a covered component.
    const QString contentDigest = "sha-256=:"
                                  + QString::fromLatin1(QCryptographicHash::hash(request.body, QCryptographicHash::Sha256).toBase64())
                                  + ":";

    QMap<QString, QString> headers = request.headers;
    headers["content-digest"] = contentDigest;

    const QStringList components = rfc9421Components();
    QStringList quoted;
    for (const QString &component: components)
        quoted << "\"" + component + "\"";

    const qint64 created = QDateTime::currentSecsSinceEpoch();
    const QString parameters = "(" + quoted.join(QLatin1Char(' ')) + ");created=" + QString::number(created)
                               + ";keyid=\"" + credentials.accessKeyId + "\";alg=\"hmac-sha256\"";

    QString base;
    for (const QString &component: components) {
        QString value;
        if (component == QLatin1String("@method"))
            value = request.method;
        else if (component == QLatin1String("@path"))
            value = request.path;
        else if (component == QLatin1String("@authority"))
            // Lowercased: authority is case-insensitive, so signer and verifier have to agree on
            // one spelling, and the server picks this one.
            value = request.authority.toLower();
        else
            value = headerOrEmpty(headers, component);
        base += "\"" + component + "\": " + value + "\n";
    }
    // The last line repeats the signature parameters exactly as they are sent, which is why the
    // same string is used here and in the Signature-Input header rather than being rebuilt.
    base += "\"@signature-params\": " + parameters;

    const QByteArray signature = hmacSha256(credentials.secretAccessKey.toUtf8(), base.toUtf8());

    return {
            {"Content-Digest", contentDigest},
            {"Signature-Input", "sig1=" + parameters},
            {"Signature", "sig1=:" + QString::fromLatin1(signature.toBase64()) + ":"},
    };
}
