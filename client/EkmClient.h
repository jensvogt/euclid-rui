#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QJsonArray>
#include <QJsonObject>

class EuclidBaseClient;

// EKM (key management service) calls: encryption keys, and the X.509 certificates the API gateway
// serves on an HTTPS listener.
//
// Certificates live here rather than with EAG because they are key material and this is where
// euclid keeps key material - one place that knows what exists, who it belongs to and when it
// expires. A gateway listener names one; see Entity::EKM::Certificate.
class EkmClient : public QObject {
    Q_OBJECT

public:
    explicit EkmClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    Q_INVOKABLE void fetchKeys(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                               const QString &sortColumn = QStringLiteral("name"),
                               const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void createKey(const QString &algorithm, int length = 128);
    Q_INVOKABLE void revokeKey(const QString &ern);
    // Schedules the key for permanent deletion after pendingWindowInDays (server default 7);
    // keyId is the key's name, i.e. what create-key/list-keys expose as "name" (not the ERN).
    Q_INVOKABLE void deleteKey(const QString &keyId, int pendingWindowInDays = 7);
    // Replaces the free text recorded with a key to say what it is for. An empty description is a
    // valid one and clears whatever the key carried; nothing else about the key is touched, which
    // is why this works on a revoked key or one scheduled for deletion too.
    Q_INVOKABLE void setKeyDescription(const QString &keyErn, const QString &description);
    // Upserts the tag unconditionally (no set-key-tag counterpart exists server-side).
    Q_INVOKABLE void addKeyTag(const QString &keyErn, const QString &key, const QString &value);
    // No-ops server-side if the key doesn't have this tag key.
    Q_INVOKABLE void deleteKeyTag(const QString &keyErn, const QString &key);

    // ── Certificates ────────────────────────────────────────────────────────

    // Paged and sorted like list-keys. Certificates are scoped to the account and the namespace
    // the session is working in, so this lists what that namespace's listeners can name.
    Q_INVOKABLE void fetchCertificates(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                       const QString &sortColumn = QStringLiteral("name"),
                                       const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void fetchCertificate(const QString &name);

    // Generates a self-signed certificate, for an installation that has to serve HTTPS before
    // anybody has bought it a real one. Nobody has vouched for the result: a client rejects it
    // until it is given the certificate as a trust anchor of its own.
    //
    // An empty commonName takes the certificate's name, which is what the server does too - a
    // certificate with an empty subject is refused by everything that reads it.
    Q_INVOKABLE void createCertificate(const QString &name, const QString &commonName = QString(),
                                       const QStringList &subjectAltNames = QStringList(),
                                       int validDays = 825, int keyBits = 2048,
                                       const QString &description = QString());

    // Uploads a certificate somebody else issued, with its private key, under a name. Both files
    // are read here and sent as text: import-certificate takes PEM in a JSON body, so there is no
    // upload in the HTTP sense to do.
    //
    // The pair is checked server-side before either is stored, and a name that already exists is
    // replaced - which is how a real certificate takes over from the self-signed one euclid
    // generated for a listener, and how a renewed one is rolled out.
    Q_INVOKABLE void importCertificate(const QString &name, const QString &description,
                                       const QUrl &certificateFile, const QUrl &privateKeyFile);

    // Writes the certificate's PEM to a local file. Only the certificate: the private key never
    // leaves the server and is not part of any response, so what is saved here is what a client
    // needs to trust the listener, not what would let anything impersonate it.
    Q_INVOKABLE void exportCertificate(const QString &name, const QUrl &targetFile);

    Q_INVOKABLE void deleteCertificate(const QString &name);

signals:
    void keysLoaded(const QVariantList &keys, int total);
    void keysFailed(const QString &message);
    void keysReload();
    void keyCreated(const QString &name);
    void keyCreateFailed(const QString &message);
    void keyDescriptionChanged(const QString &keyErn, const QString &description);
    void keyDescriptionFailed(const QString &message);
    void keyTagAdded(const QString &keyErn, const QString &key, const QString &value);
    void keyTagAddFailed(const QString &message);
    void keyTagDeleted(const QString &keyErn, const QString &key);
    void keyTagDeleteFailed(const QString &message);

    // Each entry: {name, ern, description, certificate (PEM), subject, issuer, serialNumber,
    // fingerprint, subjectAltNames, generated, notBefore, notAfter, tags, created, modified}.
    void certificatesLoaded(const QVariantList &certificates, int total);
    void certificatesFailed(const QString &message);
    void certificatesReload();
    void certificateLoaded(const QString &name, const QVariantMap &certificate);
    void certificateCreated(const QString &name, const QVariantMap &certificate);
    void certificateCreateFailed(const QString &message);
    void certificateImported(const QString &name, const QVariantMap &certificate);
    void certificateImportFailed(const QString &message);
    // Carries the path actually written, since it is what a "saved to ..." message has to say.
    void certificateExported(const QString &name, const QString &path);
    void certificateExportFailed(const QString &message);
    void certificateDeleted(const QString &name);
    void certificateDeleteFailed(const QString &message);

private:
    EuclidBaseClient *m_base;
};
