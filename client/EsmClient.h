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

    // "includeInternal" asks for euclid's own buckets as well - the one applications are deployed
    // from and the like. The server honours it for administrators only and silently ignores it for
    // everyone else, so asking is never an error, it just changes nothing.
    Q_INVOKABLE void fetchBuckets(const QString &prefix = QString(), int pageIndex = 0, int pageSize = 10,
                                  const QString &sortColumn = QStringLiteral("name"),
                                  const QString &sortDirection = QStringLiteral("asc"),
                                  bool includeInternal = false);
    // `priority` is what the bucket's notifications are sent at, and empty - the default - is a
    // bucket that states none. See setBucketPriority(), which is how it is changed afterwards.
    Q_INVOKABLE void createBucket(const QString &name, const QString &priority = QString());
    // Deletes every object in the bucket. `async` hands the work to the server's background
    // purge, which answers "accepted" and keeps deleting after the reply - the only workable way
    // for a bucket holding more objects than a request can get through before timing out. The
    // counts catch up on later refreshes rather than being right in the answer.
    //
    // `notify` is whether each removed object is announced to the bucket's subscribers as its own
    // esm.object.deleted event, which is what a purge has always done and stays the default: a
    // subscriber keeping an index of keys has to be told which ones went, and "the bucket was
    // purged" does not say. Asking for silence suits test data, where the announcing is not free
    // at either end - a purge of 1.3 million objects fed a listener's queue for hours - and is
    // wrong wherever something keeps its own record of the bucket, which then goes quietly stale
    // with no later event to reconcile it.
    Q_INVOKABLE void purgeBucket(const QString &bucketErn, bool async = false, bool notify = true);

    // Announces objects already in the bucket, as though each had just been uploaded: the same
    // esm.object.created event and the same subscription deliveries an upload would have produced.
    //
    // Nothing about the objects changes - not a byte, and not their modified times either. "Touch"
    // means what it does to listeners, not what it does to storage, which is why this issues no
    // reload: there is nothing new for a listing to show.
    //
    // `prefix` is matched against the whole key: empty announces every object in the bucket, a
    // full key announces that one object. Note that it stays a *prefix* even then - a key that
    // another key starts with selects both - so the count that comes back is what was actually
    // announced rather than what was asked for.
    //
    // `async` hands the announcing to a background thread inside ESM and answers at once with the
    // count as it stood, for a selection large enough that doing it inline outlasts the request's
    // own timeout.
    // Moves one object out of the online store, or brings it back: "archive-object" /
    // "restore-object". What a lifecycle rule does on a schedule, done by hand.
    //
    // `days` is the grace period a restore buys, and 0 - the usual case - means the one the
    // covering rule states, or euclid.modules.esm.restore-days where no rule covers the key.
    // Ignored when archiving.
    //
    // Idempotent: an object already in the state asked for is answered as it is rather than
    // refused. Refused for a directory marker, for an incomplete upload, and for anything in one
    // of euclid's own internal buckets.
    Q_INVOKABLE void setObjectArchived(const QString &objectErn, bool archived, int days = 0);

    // A bucket's lifecycle rules: what gets archived, and when. Each rule is
    // {id, prefix, archiveAfterDays, restoreDays, enabled} - see Entity::ESM::LifecycleRule.
    //
    // Not part of a bucket listing, so a page that shows them has to ask for them.
    Q_INVOKABLE void fetchBucketLifecycle(const QString &bucketErn);

    // Replaces the whole set, because that is what the server does with it: there is no "add one
    // rule" action, and sending a subset would silently drop the rest. An empty list clears them,
    // which goes out as "delete-bucket-lifecycle".
    //
    // Refused by the server for a rule without an id, for days outside 1 to 36500, for two rules
    // sharing an id, and for any rule at all on one of euclid's own internal buckets - whose
    // objects are read straight off the disk by modules that know nothing of an archive.
    //
    // Archiving is what rules decide; they never bring anything back. Objects already archived
    // stay archived when the rules change or are removed - restoring one is restore-object's job.
    Q_INVOKABLE void setBucketLifecycle(const QString &bucketErn, const QVariantList &rules);

    // Holds a bucket's events in EES, or lets the held ones go: "stop-bucket"/"start-bucket".
    //
    // Only the announcements wait. The objects are read and written exactly as before, which is
    // what makes this different from stopping a queue - a stopped bucket still accepts uploads,
    // it just does not tell anybody about them until it is started again.
    //
    // Idempotent on both sides: stopping a stopped bucket changes nothing, and starting one that
    // was never stopped releases nothing.
    Q_INVOKABLE void setBucketStopped(const QString &bucketErn, bool stopped);

    Q_INVOKABLE void touchObjects(const QString &bucketErn, const QString &prefix = QString(), bool async = false);
    // A bucket's name is part of its ERN and of every object ERN inside it, so a rename rewrites
    // all of them server-side and repoints subscriptions; the counts come back in bucketRenamed().
    // Refused (409) while a transfer server still serves the bucket, since its clients are
    // mid-session against the old ERN.
    Q_INVOKABLE void renameBucket(const QString &bucketErn, const QString &newName);
    Q_INVOKABLE void deleteBucket(const QString &bucketErn);

    // The priority the bucket's notifications carry: "LOW", "MEDIUM", "HIGH", or empty to clear it.
    //
    // Nothing about the bucket itself behaves differently - a bucket is not consumed from and has
    // no queue of its own. It is a statement handed on to the messages a subscription of this
    // bucket turns object events into, and the queue on the far side is where it has an effect.
    //
    // Empty is not MEDIUM. A bucket that says nothing leaves the target queue's own default in
    // force, which is how every bucket behaved before this existed - so clearing is a distinct
    // thing to ask for and not a synonym for the middle setting.
    //
    // Outranked by an object's own: a priority in an object's system attributes is a statement
    // about that object where this is one about all of them, so that one wins.
    Q_INVOKABLE void setBucketPriority(const QString &bucketErn, const QString &priority);
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
    // One level of a bucket: the objects whose key sits directly in `level`, and the directories
    // one step below it. `level` ends in "/" - "DEMODLI/" - or is empty for the bucket's root.
    //
    // This is "list-objects" with a delimiter, which is a different question from the prefix
    // listing above: that one answers with everything beneath a prefix, this one with what is in
    // it. ESM keeps each object's parent path as a field and indexes it, so a level is a lookup
    // rather than a match over every key - and the directories come back whether or not anything
    // was ever written to mark them, including ones that hold only other directories.
    //
    // Answers through objectsLevelLoaded(); the directories are full paths, each ending in "/".
    Q_INVOKABLE void fetchObjectLevel(const QString &bucketErn, const QString &level = QString(),
                                      int pageIndex = 0, int pageSize = 200,
                                      const QString &sortDirection = QStringLiteral("asc"),
                                      bool includeDirectories = false);

    Q_INVOKABLE void deleteObject(const QString &bucketErn, const QString &objectErn);

    // How big one object is, for a caller that wants nothing else about it. ESM has no head-object
    // or get-object-metadata action, so this is "list-objects" narrowed to the one key and read for
    // its size - deliberately not fetchObjects(), whose objectsLoaded/objectsFailed carry a whole
    // listing and are what the objects table binds to. A page asking about a single object would
    // otherwise hand that table a one-row result for a bucket it is not even showing.
    //
    // `prefix` is a prefix and not an exact match, so the reply can hold neighbours - "app-1.4.jar"
    // when asked about "app-1.4.ja" would not come up, but "app-1.4.jar.sha256" does. The exact key
    // is picked out here, and its absence is reported as a failure rather than as a size of zero:
    // an artifact that is not there is a different thing from an empty one.
    Q_INVOKABLE void fetchObjectSize(const QString &bucketErn, const QString &key);

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
    //
    // `priority` is this one object's: "LOW", "MEDIUM", "HIGH", or empty to say nothing about it
    // and let the bucket's own setting stand. It travels as the "priority" system attribute, which
    // is euclid's own envelope rather than the caller's metadata - kept apart from the object's
    // attributes, and not returned by list-object-attributes.
    //
    // More specific than the bucket's, and that is the order it is applied in: a bucket says
    // "everything from here is urgent", this says "this one is", so this wins. The queue a
    // subscription delivers the notification to is where either of them decides anything; the
    // object itself is stored and served the same whatever it says.
    Q_INVOKABLE void uploadObject(const QString &bucketErn, const QString &key, const QUrl &fileUrl,
                                  const QString &priority = QString());

    // Replaces an object's content with `text`, encoded UTF-8, through the same "put-object" an
    // upload uses. This rewrites the object rather than patching it: size, checksum and content
    // type are all derived again from the new bytes, and the bucket's subscribers hear about it
    // exactly as they would for an upload.
    //
    // No content type is sent, because none is read: the server sniffs it from the bytes. A
    // document saved as JSON comes back as JSON without the caller naming a type, and one edited
    // until it is no longer JSON comes back as whatever it now is.
    //
    // `attributes` are the object's current user attributes, in the {name: {type, value}} form
    // list-object-attributes returns, and they have to be passed: an upload that names none stores
    // none, so a caller that omits them deletes every attribute the object had. Euclid's own
    // system attributes cannot be preserved this way - nothing reads them back out - so an object
    // carrying any loses them here.
    Q_INVOKABLE void saveObjectContent(const QString &bucketErn, const QString &key, const QString &text,
                                       const QVariantMap &attributes = QVariantMap());

signals:
    void bucketsLoaded(const QVariantList &buckets, int total);
    void bucketsFailed(const QString &message);
    void bucketsReload();
    void bucketCreated(const QString &name);
    void bucketCreateFailed(const QString &message);
    // `objects` and `subscriptions` are how many of each the server rewrote to the new ERN.
    void bucketRenamed(const QString &name, const QString &ern, int objects, int subscriptions);
    void bucketRenameFailed(const QString &message);
    // A purge the server accepted. `async` says whether it is still running: false means the
    // objects are gone, true means the server is working through them and the bucket's counts will
    // fall over the next refreshes. `objects` is how many there were when it started.
    void bucketPurged(const QString &bucketErn, bool async, int objects);
    // A touch the server accepted. `prefix` is what it selected on, echoed back so a caller that
    // touched one key can say which. `async` says whether it is still running: false means every
    // selected object has been announced and `objects` is how many that was, true means a
    // background thread is working through them and `objects` is how many there were when it
    // started. Nothing in any listing changes either way.
    void objectsTouched(const QString &bucketErn, const QString &prefix, bool async, int objects);
    // The priority as the server stored it - uppercased, or empty for a bucket that now says
    // nothing. `name` comes back with it because the answer is about the bucket, not the ERN.
    void bucketPriorityChanged(const QString &bucketErn, const QString &name, const QString &priority);
    // `count` is how many events are held now (stopping) or how many were released (starting).
    // The object's state as it now stands: "STANDARD" or "ARCHIVED". restoredUntil is when a
    // restored object may be archived again, and is empty for one that is archived.
    void objectLifecycleChanged(const QString &objectErn, const QString &lifecycleState, const QString &restoredUntil);
    void objectLifecycleFailed(const QString &message);
    void bucketLifecycleLoaded(const QString &bucketErn, const QVariantList &rules);
    void bucketLifecycleChanged(const QString &bucketErn, const QVariantList &rules);
    void bucketLifecycleFailed(const QString &bucketErn, const QString &message);
    void bucketStoppedChanged(const QString &bucketErn, bool stopped, int count);
    void bucketStoppedFailed(const QString &message);
    void bucketPriorityFailed(const QString &message);
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
    // One level: the objects in it, the directories below it, and how many objects the level
    // holds in all - which is what the pager counts, and is not the size of the subtree.
    void objectsLevelLoaded(const QString &bucketErn, const QString &level, const QVariantList &objects,
                            const QStringList &directories, int total);
    void objectsFailed(const QString &bucketErn, const QString &message);

    // Both carry the bucket and key back, because these reach every listener and a page showing one
    // object's size has no other way to tell its own answer from somebody else's. qint64 rather
    // than int: an artifact outgrows 2 GB long before it outgrows what ESM will store.
    void objectSizeLoaded(const QString &bucketErn, const QString &key, qint64 size);
    void objectSizeFailed(const QString &bucketErn, const QString &key, const QString &message);
    void objectsReload(const QString &bucketErn);
    void objectUploaded(const QString &bucketErn, const QString &key);
    void objectUploadFailed(const QString &message);
    // Carries the object as the server stored it - {ern, bucketErn, key, size, status,
    // contentType, md5Sum} - so a details page can correct the size and checksum it is showing
    // without re-reading the listing it was opened from.
    //
    // Kept apart from objectUploaded/objectUploadFailed: a details page has to tell its own
    // editor's save from any other upload, and objectUploadFailed carries no key to match on.
    void objectContentSaved(const QString &bucketErn, const QString &key, const QVariantMap &object);
    void objectContentSaveFailed(const QString &bucketErn, const QString &key, const QString &message);
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

    // The object's priority rides along the whole way down: a single-part upload carries it on
    // "put-object", a multipart one on "complete-upload", which is where the parts become an
    // object and the only point in that flow with an object to attach it to.
    void uploadSinglePart(const QString &bucketErn, const QString &key, const QByteArray &data,
                          const QString &priority = QString());
    void beginMultipartUpload(const QString &bucketErn, const QString &key, const QString &path, qint64 fileSize,
                              const QString &priority = QString());
    void uploadNextPart(const QString &bucketErn, const QString &key, const QString &path, qint64 fileSize,
                         const QString &uploadId, long partNumber, qint64 bytesSent, const QString &priority);
    void completeMultipartUpload(const QString &bucketErn, const QString &key, const QString &uploadId,
                                 const QString &priority);

    EuclidBaseClient *m_base;
};
