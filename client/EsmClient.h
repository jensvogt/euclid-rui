#pragma once

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <functional>

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
    // A bucket's name is part of its ERN and of every object ERN inside it, so a rename rewrites
    // all of them server-side and repoints subscriptions; the counts come back in bucketRenamed().
    // Refused (409) while a transfer server still serves the bucket, since its clients are
    // mid-session against the old ERN.
    Q_INVOKABLE void renameBucket(const QString &bucketErn, const QString &newName);
    Q_INVOKABLE void deleteBucket(const QString &bucketErn);
    // Upserts the tag unconditionally (unlike set-bucket-tag, this doesn't require the key to
    // already exist), matching an "Add" button's semantics.
    Q_INVOKABLE void addBucketTag(const QString &bucketErn, const QString &key, const QString &value);
    // No-ops server-side if the bucket doesn't have this tag key.
    Q_INVOKABLE void deleteBucketTag(const QString &bucketErn, const QString &key);

    // Encryption at rest. Both calls are settings about the *next* object written to the bucket and
    // nothing else: neither rewrites what the bucket already holds, and neither touches an EKM key
    // beyond pointing the bucket at one. Every object records the key it was written under, so a
    // bucket can serve encrypted and plaintext objects side by side without a client noticing.
    //
    // `keyId` is an EKM key's ERN or its key ID; left empty, the server creates an AES-256 key for
    // the bucket. Enabling on an already-encrypted bucket rotates: new objects go under the new
    // key, existing ones keep naming the old one.
    Q_INVOKABLE void enableBucketEncryption(const QString &bucketErn, const QString &keyId = QString());
    Q_INVOKABLE void disableBucketEncryption(const QString &bucketErn);

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

    // Reads a whole object back in one request, for showing it rather than saving it to disk -
    // "get-object" is the same call the CLI's download-file tries before falling back to the
    // multipart flow. `maxBytes` is the cutoff the server enforces: an object that size or larger
    // is refused with 413 rather than streamed, so a viewer can name what it is willing to render
    // and be sure the answer never exceeds it.
    //
    // The bytes come back as UTF-8 text, since that is the only thing worth showing. Anything that
    // is not valid UTF-8 decodes to replacement characters, which is what tells a viewer it was
    // handed something binary.
    Q_INVOKABLE void fetchObjectContent(const QString &bucketErn, const QString &key, int maxBytes);
    // The same call for content that is not text: the bytes come back base64 encoded, since that is
    // the only way they survive being carried as a string - decoding them as UTF-8 would replace
    // everything that is not valid UTF-8, which for an image is most of it.
    Q_INVOKABLE void fetchObjectContentBase64(const QString &bucketErn, const QString &key, int maxBytes);

    // Saves an object to a local file, whatever its size - the answer for everything the viewer
    // above refuses. Always takes the multipart route (create-download, then one download-part per
    // kMultipartThreshold bytes, then complete-download): a small object costs two extra round
    // trips that way, and nothing has to guess a size before asking for it.
    //
    // Parts are fetched one after another and appended in order, unlike the CLI's parallel
    // download - a GUI has one event loop and no reason to saturate the link.
    Q_INVOKABLE void downloadObject(const QString &bucketErn, const QString &key, const QUrl &fileUrl);

    // Renaming and copying are key operations, not data ones: an object's bytes live in a file
    // named after an internal ID and only its row says which key that file answers to, so a rename
    // costs the same whatever the object's size. A copy is the one that duplicates the file, since
    // the two objects have to be able to outlive each other.
    //
    // Both refuse rather than overwrite when something is already stored at the target key, which
    // is why they report failure separately from a listing that failed to load.
    Q_INVOKABLE void renameObject(const QString &bucketErn, const QString &key, const QString &newKey);
    Q_INVOKABLE void copyObject(const QString &sourceBucketErn, const QString &sourceKey,
                                const QString &targetBucketErn, const QString &targetKey);
    // Same request shape as copyObject(), and the same freedom to cross buckets - the difference
    // is that the source object is gone afterwards, and its bytes are handed to the target rather
    // than duplicated.
    Q_INVOKABLE void moveObject(const QString &sourceBucketErn, const QString &sourceKey,
                                const QString &targetBucketErn, const QString &targetKey);

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
    // `objects` and `subscriptions` are how many of each the server rewrote to the new ERN.
    void bucketRenamed(const QString &name, const QString &ern, int objects, int subscriptions);
    void bucketRenameFailed(const QString &message);
    void bucketTagAdded(const QString &bucketErn, const QString &key, const QString &value);
    void bucketTagAddFailed(const QString &message);
    void bucketTagDeleted(const QString &bucketErn, const QString &key);
    void bucketTagDeleteFailed(const QString &message);
    // `existingObjects` is how many objects the bucket already held: they are left exactly as they
    // were stored, so this is the number still in the clear after encryption was switched on.
    // `keyCreated` says the server minted the key for this bucket rather than being handed one.
    void bucketEncryptionEnabled(const QString &bucketErn, const QString &keyErn, const QString &keyId,
                                 const QString &algorithm, bool keyCreated, int existingObjects);
    // `encryptedObjects` is how many objects are still stored encrypted - nothing is decrypted by
    // switching encryption off, and while this is above zero the keys those objects name must stay
    // in EKM. `previousKeyErn` is empty when the bucket was not encrypting to begin with.
    void bucketEncryptionDisabled(const QString &bucketErn, const QString &previousKeyErn,
                                  const QString &previousKeyId, int encryptedObjects);
    void bucketEncryptionFailed(const QString &message);

    // Objects
    void objectsLoaded(const QString &bucketErn, const QVariantList &objects, int total);
    void objectsFailed(const QString &bucketErn, const QString &message);
    void objectsReload(const QString &bucketErn);
    void objectUploaded(const QString &bucketErn, const QString &key);
    void objectUploadFailed(const QString &message);
    // The object's bytes as UTF-8 text. Carries the bucket and key it was asked for, since a view
    // can have moved on to another object by the time this arrives.
    void objectContentLoaded(const QString &bucketErn, const QString &key, const QString &content);
    // The same bytes base64 encoded, for whatever is going to decode them itself.
    void objectContentBase64Loaded(const QString &bucketErn, const QString &key, const QString &base64);
    // Shared by both: they are the same request and fail for the same reasons.
    void objectContentFailed(const QString &bucketErn, const QString &key, const QString &message);
    // Carries the local path the object was written to, which is the only thing worth reporting
    // once it is on disk.
    void objectDownloaded(const QString &bucketErn, const QString &key, const QString &path);
    void objectDownloadFailed(const QString &message);
    // Emitted after each part lands; bytesTotal is the object's whole size.
    void downloadProgress(const QString &bucketErn, const QString &key, qint64 bytesReceived, qint64 bytesTotal);
    // Carries the key it ended up under, so a view can say what happened rather than only that
    // something did.
    void objectRenamed(const QString &bucketErn, const QString &key);
    void objectCopied(const QString &bucketErn, const QString &key);
    void objectMoved(const QString &bucketErn, const QString &key);
    // Rename and copy share one failure signal: both fail for the same reasons (the target key is
    // taken, the object is gone, the caller may not write that bucket) and both are reported in
    // the dialog the user is looking at.
    void objectTransferFailed(const QString &message);
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
    // The one "get-object" both fetchObjectContent() and fetchObjectContentBase64() issue; they
    // differ only in what they do with the bytes, and share the failure signal.
    void requestObject(const QString &bucketErn, const QString &key, int maxBytes,
                       const std::function<void(const QByteArray &)> &onBytes);

    void downloadNextPart(const QString &bucketErn, const QString &key, const QString &path,
                          const QString &downloadId, qint64 fileSize, long partNumber, qint64 bytesReceived);
    void completeDownload(const QString &bucketErn, const QString &key, const QString &path, const QString &downloadId);

    void uploadSinglePart(const QString &bucketErn, const QString &key, const QByteArray &data);
    void beginMultipartUpload(const QString &bucketErn, const QString &key, const QString &path, qint64 fileSize);
    void uploadNextPart(const QString &bucketErn, const QString &key, const QString &path, qint64 fileSize,
                         const QString &uploadId, long partNumber, qint64 bytesSent);
    void completeMultipartUpload(const QString &bucketErn, const QString &key, const QString &uploadId);

    EuclidBaseClient *m_base;
};
