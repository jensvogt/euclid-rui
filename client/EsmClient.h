#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

class EuclidBaseClient;

// ESM (bucket/object storage service) calls: buckets and (eventually) their objects.
class EsmClient : public QObject {
    Q_OBJECT

public:
    explicit EsmClient(EuclidBaseClient *baseClient, QObject *parent = nullptr);

    Q_INVOKABLE void fetchBuckets(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                  const QString &sortColumn = QStringLiteral("name"),
                                  const QString &sortDirection = QStringLiteral("asc"));
    Q_INVOKABLE void createBucket(const QString &name);
    Q_INVOKABLE void purgeBucket(const QString &bucketErn);
    Q_INVOKABLE void deleteBucket(const QString &bucketErn);
    // Upserts the tag unconditionally (unlike set-bucket-tag, this doesn't require the key to
    // already exist), matching an "Add" button's semantics.
    Q_INVOKABLE void addBucketTag(const QString &bucketErn, const QString &key, const QString &value);
    // No-ops server-side if the bucket doesn't have this tag key.
    Q_INVOKABLE void deleteBucketTag(const QString &bucketErn, const QString &key);

    // Objects
    // A bucket is flat: a directory exists only as a zero-byte object whose key ends in "/" (the
    // marker a transfer server writes on MKD). The server leaves those out of listings unless
    // `includeDirectories` is set, so a tree view has to ask for them - otherwise a folder that
    // holds no files, or holds only other empty folders, is invisible.
    Q_INVOKABLE void fetchObjects(const QString &bucketErn, const QString &prefix = QString(), int pageIndex = 0, int pageSize = 100,
                                  const QString &sortColumn = QStringLiteral("key"),
                                  const QString &sortDirection = QStringLiteral("asc"),
                                  bool includeDirectories = false);
    Q_INVOKABLE void deleteObject(const QString &bucketErn, const QString &objectErn);

    // User-defined object attributes. One call changes one attribute: ESM replaced the old
    // bulk "set-object-attributes" with add/set/delete/list, each strict about whether the name
    // already exists - add fails with 409 on a duplicate, set and delete with 404 on a name that
    // was never stored, so a typo cannot quietly create or drop the wrong thing.
    //
    // `type` is one of string/int/long/float/double/bool and decides how `value` is encoded, the
    // JSON shape Dto::COM::Variant reads: {"type": ..., "value": ...}.
    Q_INVOKABLE void fetchObjectAttributes(const QString &objectErn);
    Q_INVOKABLE void addObjectAttribute(const QString &objectErn, const QString &name, const QString &type, const QVariant &value);
    Q_INVOKABLE void setObjectAttribute(const QString &objectErn, const QString &name, const QString &type, const QVariant &value);
    Q_INVOKABLE void deleteObjectAttribute(const QString &objectErn, const QString &name);
    // Uploads the local file at fileUrl (e.g. from a QML FileDialog's selectedFile) as an object
    // under the given key. Files under kMultipartThreshold go through "put-object" in one request;
    // larger files are split into kMultipartThreshold-sized parts and sent through the
    // create-upload/upload-part/complete-upload flow instead, matching the CLI's upload-file.
    Q_INVOKABLE void uploadObject(const QString &bucketErn, const QString &key, const QUrl &fileUrl);

signals:
    void bucketsLoaded(const QVariantList &buckets, int total);
    void bucketsFailed(const QString &message);
    void bucketsReload();
    void bucketCreated(const QString &name);
    void bucketCreateFailed(const QString &message);
    void bucketTagAdded(const QString &bucketErn, const QString &key, const QString &value);
    void bucketTagAddFailed(const QString &message);
    void bucketTagDeleted(const QString &bucketErn, const QString &key);
    void bucketTagDeleteFailed(const QString &message);

    // Objects
    void objectsLoaded(const QString &bucketErn, const QVariantList &objects, int total);
    void objectsFailed(const QString &bucketErn, const QString &message);
    void objectsReload(const QString &bucketErn);
    void objectUploaded(const QString &bucketErn, const QString &key);
    void objectUploadFailed(const QString &message);
    // Emitted after each part of a multipart upload completes; bytesTotal is the whole file's size.
    // Never emitted for single-request ("put-object") uploads.
    void uploadProgress(const QString &bucketErn, const QString &key, qint64 bytesSent, qint64 bytesTotal);
    // The object's whole attribute map, {name: {type, value}}, as "list-object-attributes"
    // returned it.
    void objectAttributesLoaded(const QString &objectErn, const QVariantMap &attributes);
    // One attribute was added, changed or removed. Carries no value: each mutation returns only
    // the attribute it touched, and re-reading the list is what keeps the view authoritative.
    void objectAttributeChanged(const QString &objectErn, const QString &name);
    void objectAttributesFailed(const QString &message);

private:
    void uploadSinglePart(const QString &bucketErn, const QString &key, const QByteArray &data);
    void beginMultipartUpload(const QString &bucketErn, const QString &key, const QString &path, qint64 fileSize);
    void uploadNextPart(const QString &bucketErn, const QString &key, const QString &path, qint64 fileSize,
                         const QString &uploadId, long partNumber, qint64 bytesSent);
    void completeMultipartUpload(const QString &bucketErn, const QString &key, const QString &uploadId);

    EuclidBaseClient *m_base;
};
