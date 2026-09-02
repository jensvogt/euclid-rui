#include "EsmClient.h"
#include "EuclidBaseClient.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QVariantMap>

namespace {
// Matches the euclid CLI's DEFAULT_PART_SIZE (euclid/cli/include/euclid/cli/esm/EsmCli.h): files at
// or above this size go through create-upload/upload-part/complete-upload, split into parts of
// this same size; smaller files go through "put-object" in a single request.
constexpr qint64 kMultipartThreshold = 5 * 1024 * 1024;
}

EsmClient::EsmClient(EuclidBaseClient *baseClient, QObject *parent) : QObject(parent), m_base(baseClient) {}

void EsmClient::fetchBuckets(const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("esm", "list-buckets", body, true,
         [this](const QJsonObject &response) {
             QVariantList buckets;
             for (const QJsonArray array = response.value("buckets").toArray(); const auto &value : array) {
                 const QJsonObject bucket = value.toObject();
                 QVariantMap entry;
                 entry["name"] = bucket.value("name").toString();
                 entry["ern"] = bucket.value("ern").toString();
                 entry["owner"] = bucket.value("owner").toString();
                 entry["size"] = bucket.value("size").toInt();
                 entry["objects"] = bucket.value("objects").toInt();
                 entry["tags"] = bucket.value("tags").toObject().toVariantMap();
                 entry["encrypted"] = bucket.value("encrypted").toBool();
                 entry["encryptionKeyErn"] = bucket.value("encryptionKeyErn").toString();
                 entry["created"] = bucket.value("created").toString();
                 entry["modified"] = bucket.value("modified").toString();
                 buckets << entry;
             }
             emit bucketsLoaded(buckets, response.value("total").toInt());
         },
         [this](const QString &message) {
             emit bucketsFailed(message);
         });
}

void EsmClient::createBucket(const QString &name) {
    QJsonObject body;
    body["name"] = name;

    m_base->post("esm", "create-bucket", body, true,
         [this, name](const QJsonObject &response) {
             emit bucketCreated(name);
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketCreateFailed(message);
         });
}

void EsmClient::purgeBucket(const QString &bucketErn) {
    QJsonObject body;
    body["ern"] = bucketErn;
    body["prefix"] = "";

    m_base->post("esm", "purge-bucket", body, true,
         [this, bucketErn](const QJsonObject &response) {
             emit objectsReload(bucketErn);
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketsFailed(message);
         });
}

void EsmClient::renameBucket(const QString &bucketErn, const QString &newName) {
    QJsonObject body;
    body["ern"] = bucketErn;
    body["newName"] = newName;

    m_base->post("esm", "rename-bucket", body, true,
         [this](const QJsonObject &response) {
             emit bucketRenamed(response.value("name").toString(), response.value("ern").toString(),
                                response.value("objects").toInt(), response.value("subscriptions").toInt());
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketRenameFailed(message);
         });
}

void EsmClient::deleteBucket(const QString &bucketErn) {
    QJsonObject body;
    body["ern"] = bucketErn;

    m_base->post("esm", "delete-bucket", body, true,
         [this](const QJsonObject &response) {
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketsFailed(message);
         });
}

void EsmClient::addBucketTag(const QString &bucketErn, const QString &key, const QString &value) {
    QJsonObject body;
    body["ern"] = bucketErn;
    body["key"] = key;
    body["value"] = value;

    m_base->post("esm", "add-bucket-tag", body, true,
         [this, bucketErn, key, value](const QJsonObject &response) {
             emit bucketTagAdded(bucketErn, key, value);
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketTagAddFailed(message);
         });
}

void EsmClient::deleteBucketTag(const QString &bucketErn, const QString &key) {
    QJsonObject body;
    body["ern"] = bucketErn;
    body["key"] = key;

    m_base->post("esm", "delete-bucket-tag", body, true,
         [this, bucketErn, key](const QJsonObject &response) {
             emit bucketTagDeleted(bucketErn, key);
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketTagDeleteFailed(message);
         });
}

void EsmClient::enableBucketEncryption(const QString &bucketErn, const QString &keyId) {
    QJsonObject body;
    body["bucketErn"] = bucketErn;
    body["keyId"] = keyId;

    m_base->post("esm", "enable-encryption", body, true,
         [this, bucketErn](const QJsonObject &response) {
             emit bucketEncryptionEnabled(bucketErn, response.value("keyErn").toString(), response.value("keyId").toString(),
                                          response.value("algorithm").toString(), response.value("keyCreated").toBool(),
                                          response.value("existingObjects").toInt());
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketEncryptionFailed(message);
         });
}

void EsmClient::disableBucketEncryption(const QString &bucketErn) {
    QJsonObject body;
    body["bucketErn"] = bucketErn;

    m_base->post("esm", "disable-encryption", body, true,
         [this, bucketErn](const QJsonObject &response) {
             emit bucketEncryptionDisabled(bucketErn, response.value("previousKeyErn").toString(),
                                           response.value("previousKeyId").toString(),
                                           response.value("encryptedObjects").toInt());
             emit bucketsReload();
         },
         [this](const QString &message) {
             emit bucketEncryptionFailed(message);
         });
}

void EsmClient::fetchObjects(const QString &bucketErn, const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection, const bool includeDirectories) {
    QJsonObject body;
    body["bucketErn"] = bucketErn;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;
    body["includeDirectories"] = includeDirectories;

    m_base->post("esm", "list-objects", body, true,
         [this, bucketErn](const QJsonObject &response) {
             QVariantList objects;
             for (const QJsonArray array = response.value("objects").toArray(); const auto &value : array) {
                 const QJsonObject object = value.toObject();
                 QVariantMap entry;
                 const QString key = object.value("key").toString();
                 entry["key"] = key;
                 // Derived, not sent: the wire format has no directory flag, the trailing "/" in
                 // the key IS the flag (Entity::ESM::IsDirectoryKey server-side).
                 entry["isDirectory"] = key.endsWith(QLatin1Char('/'));
                 entry["ern"] = object.value("ern").toString();
                 entry["bucketErn"] = object.value("bucketErn").toString();
                 entry["size"] = object.value("size").toInteger();
                 entry["status"] = object.value("status").toString();
                 entry["contentType"] = object.value("contentType").toString();
                 entry["md5Sum"] = object.value("md5Sum").toString();
                 // {name: {type, value}} - user-defined attributes, typed server-side by
                 // Dto::COM::Variant rather than being plain strings.
                 entry["attributes"] = object.value("attributes").toObject().toVariantMap();
                 entry["created"] = object.value("created").toString();
                 entry["modified"] = object.value("modified").toString();
                 objects << entry;
             }
             emit objectsLoaded(bucketErn, objects, response.value("total").toInt());
         },
         [this, bucketErn](const QString &message) {
             emit objectsFailed(bucketErn, message);
         });
}

void EsmClient::deleteObject(const QString &bucketErn, const QString &objectErn) {
    QJsonObject body;
    body["ern"] = objectErn;

    m_base->post("esm", "delete-object", body, true,
         [this, bucketErn](const QJsonObject &response) {
             emit objectsReload(bucketErn);
         },
         [this](const QString &message) {
             emit objectsFailed(QString(), message);
         });
}

void EsmClient::requestObject(const QString &bucketErn, const QString &key, const int maxBytes,
                              const std::function<void(const QByteArray &)> &onBytes) {
    QVariantMap headers;
    headers["x-euclid-bucket-ern"] = bucketErn;
    headers["x-euclid-key"] = key;
    // The server compares the object's size against this and refuses anything at or above it, so
    // the cutoff belongs to whoever is going to render the answer.
    headers["x-euclid-part-size"] = QString::number(maxBytes);

    m_base->postForBytes("esm", "get-object", headers, onBytes,
         [this, bucketErn, key](const QString &message) {
             emit objectContentFailed(bucketErn, key, message);
         });
}

void EsmClient::fetchObjectContent(const QString &bucketErn, const QString &key, const int maxBytes) {
    requestObject(bucketErn, key, maxBytes,
         [this, bucketErn, key](const QByteArray &data) {
             emit objectContentLoaded(bucketErn, key, QString::fromUtf8(data));
         });
}

void EsmClient::fetchObjectContentBase64(const QString &bucketErn, const QString &key, const int maxBytes) {
    requestObject(bucketErn, key, maxBytes,
         [this, bucketErn, key](const QByteArray &data) {
             // Latin-1 because base64 is ASCII by construction: this only widens each character,
             // it does not interpret anything.
             emit objectContentBase64Loaded(bucketErn, key, QString::fromLatin1(data.toBase64()));
         });
}

void EsmClient::downloadObject(const QString &bucketErn, const QString &key, const QUrl &fileUrl) {
    const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();

    // Created and truncated before anything is asked of the server: the parts are appended as they
    // arrive, so whatever the file held before must be gone first - and a path that cannot be
    // written is worth finding out about now rather than one round trip into the download.
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit objectDownloadFailed(QStringLiteral("Could not open %1 for writing: %2").arg(path, file.errorString()));
        return;
    }
    file.close();

    QJsonObject body;
    body["bucketErn"] = bucketErn;
    body["key"] = key;

    m_base->post("esm", "create-download", body, true,
         [this, bucketErn, key, path](const QJsonObject &response) {
             const QString downloadId = response.value("downloadId").toString();
             // Through double: an object's size is a JSON number that outgrows an int long before
             // it outgrows what this can download.
             const auto fileSize = static_cast<qint64>(response.value("size").toDouble());
             // An empty object has no parts to ask for - the empty file just created is already
             // all of it - but the download session still has to be closed.
             if (fileSize <= 0) {
                 completeDownload(bucketErn, key, path, downloadId);
                 return;
             }
             downloadNextPart(bucketErn, key, path, downloadId, fileSize, 1, 0);
         },
         [this](const QString &message) {
             emit objectDownloadFailed(message);
         });
}

void EsmClient::downloadNextPart(const QString &bucketErn, const QString &key, const QString &path,
                                 const QString &downloadId, const qint64 fileSize, const long partNumber, const qint64 bytesReceived) {
    QVariantMap headers;
    headers["x-euclid-download-id"] = downloadId;
    headers["x-euclid-part-number"] = QString::number(partNumber);
    headers["x-euclid-part-size"] = QString::number(kMultipartThreshold);

    m_base->postForBytes("esm", "download-part", headers,
         [this, bucketErn, key, path, downloadId, fileSize, partNumber, bytesReceived](const QByteArray &data) {
             // Nothing else would end the recursion if the server kept answering with nothing, and
             // an object that never finishes arriving is a failure however politely it is reported.
             if (data.isEmpty()) {
                 emit objectDownloadFailed(QStringLiteral("Download stopped: part %1 came back empty").arg(partNumber));
                 return;
             }

             QFile file(path);
             if (!file.open(QIODevice::WriteOnly | QIODevice::Append)) {
                 emit objectDownloadFailed(QStringLiteral("Could not write to %1: %2").arg(path, file.errorString()));
                 return;
             }
             file.write(data);
             file.close();

             const qint64 received = bytesReceived + data.size();
             emit downloadProgress(bucketErn, key, received, fileSize);

             if (received >= fileSize) {
                 completeDownload(bucketErn, key, path, downloadId);
                 return;
             }
             downloadNextPart(bucketErn, key, path, downloadId, fileSize, partNumber + 1, received);
         },
         [this](const QString &message) {
             emit objectDownloadFailed(message);
         });
}

void EsmClient::completeDownload(const QString &bucketErn, const QString &key, const QString &path, const QString &downloadId) {
    QJsonObject body;
    body["downloadId"] = downloadId;

    // complete-download only drops the server's scratch directory for the session. The object is
    // already on disk by now, so failing to close the session is not a failed download - reporting
    // it as one would send the user looking for a file that is sitting right where they asked.
    m_base->post("esm", "complete-download", body, true,
         [this, bucketErn, key, path](const QJsonObject &response) {
             emit objectDownloaded(bucketErn, key, path);
         },
         [this, bucketErn, key, path](const QString &message) {
             emit objectDownloaded(bucketErn, key, path);
         });
}

void EsmClient::renameObject(const QString &bucketErn, const QString &key, const QString &newKey) {
    QJsonObject body;
    body["bucketErn"] = bucketErn;
    body["key"] = key;
    body["newKey"] = newKey;

    m_base->post("esm", "rename-object", body, true,
         [this, bucketErn, newKey](const QJsonObject &response) {
             emit objectRenamed(bucketErn, newKey);
             emit objectsReload(bucketErn);
         },
         [this](const QString &message) {
             emit objectTransferFailed(message);
         });
}

void EsmClient::copyObject(const QString &sourceBucketErn, const QString &sourceKey,
                           const QString &targetBucketErn, const QString &targetKey) {
    QJsonObject body;
    body["sourceBucketErn"] = sourceBucketErn;
    body["sourceKey"] = sourceKey;
    body["targetBucketErn"] = targetBucketErn;
    body["targetKey"] = targetKey;

    m_base->post("esm", "copy-object", body, true,
         [this, sourceBucketErn, targetBucketErn, targetKey](const QJsonObject &response) {
             emit objectCopied(targetBucketErn, targetKey);
             // The target listing gained an object; the source is what the user is most likely
             // looking at, so reload it too when the copy crossed buckets.
             emit objectsReload(targetBucketErn);
             if (sourceBucketErn != targetBucketErn)
                 emit objectsReload(sourceBucketErn);
         },
         [this](const QString &message) {
             emit objectTransferFailed(message);
         });
}

void EsmClient::moveObject(const QString &sourceBucketErn, const QString &sourceKey,
                           const QString &targetBucketErn, const QString &targetKey) {
    QJsonObject body;
    body["sourceBucketErn"] = sourceBucketErn;
    body["sourceKey"] = sourceKey;
    body["targetBucketErn"] = targetBucketErn;
    body["targetKey"] = targetKey;

    m_base->post("esm", "move-object", body, true,
         [this, sourceBucketErn, targetBucketErn, targetKey](const QJsonObject &response) {
             emit objectMoved(targetBucketErn, targetKey);
             // Unlike a copy, both listings always changed: the object left one and arrived in the
             // other, so the source is reloaded even when it is the same bucket.
             emit objectsReload(targetBucketErn);
             if (sourceBucketErn != targetBucketErn)
                 emit objectsReload(sourceBucketErn);
         },
         [this](const QString &message) {
             emit objectTransferFailed(message);
         });
}

namespace {
// {"type": ..., "value": ...} - the JSON shape Dto::COM::Variant reads. The value has to carry the
// JSON type its "type" field names: a "long" holding a string makes the server throw rather than
// answer, so callers validate before getting here.
QJsonObject variantValue(const QString &type, const QVariant &value) {
    QJsonValue encoded;
    if (type == QLatin1String("int") || type == QLatin1String("long"))
        encoded = QJsonValue(value.toLongLong());
    else if (type == QLatin1String("double") || type == QLatin1String("float"))
        encoded = QJsonValue(value.toDouble());
    else if (type == QLatin1String("bool"))
        encoded = QJsonValue(value.toBool());
    else
        encoded = QJsonValue(value.toString());
    return QJsonObject{{"type", type}, {"value", encoded}};
}
}

void EsmClient::fetchObjectAttributes(const QString &objectErn) {
    QJsonObject body;
    body["ern"] = objectErn;

    m_base->post("esm", "list-object-attributes", body, true,
         [this, objectErn](const QJsonObject &response) {
             emit objectAttributesLoaded(objectErn, response.value("attributes").toObject().toVariantMap());
         },
         [this](const QString &message) {
             emit objectAttributesFailed(message);
         });
}

void EsmClient::addObjectAttribute(const QString &objectErn, const QString &name, const QString &type, const QVariant &value) {
    QJsonObject body;
    body["ern"] = objectErn;
    body["name"] = name;
    body["value"] = variantValue(type, value);

    m_base->post("esm", "add-object-attribute", body, true,
         [this, objectErn, name](const QJsonObject &response) {
             emit objectAttributeChanged(objectErn, name);
         },
         [this](const QString &message) {
             emit objectAttributesFailed(message);
         });
}

void EsmClient::setObjectAttribute(const QString &objectErn, const QString &name, const QString &type, const QVariant &value) {
    QJsonObject body;
    body["ern"] = objectErn;
    body["name"] = name;
    body["value"] = variantValue(type, value);

    m_base->post("esm", "set-object-attribute", body, true,
         [this, objectErn, name](const QJsonObject &response) {
             emit objectAttributeChanged(objectErn, name);
         },
         [this](const QString &message) {
             emit objectAttributesFailed(message);
         });
}

void EsmClient::deleteObjectAttribute(const QString &objectErn, const QString &name) {
    QJsonObject body;
    body["ern"] = objectErn;
    body["name"] = name;

    m_base->post("esm", "delete-object-attribute", body, true,
         [this, objectErn, name](const QJsonObject &response) {
             emit objectAttributeChanged(objectErn, name);
         },
         [this](const QString &message) {
             emit objectAttributesFailed(message);
         });
}

void EsmClient::uploadObject(const QString &bucketErn, const QString &key, const QUrl &fileUrl) {
    const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    const qint64 fileSize = QFileInfo(path).size();

    if (fileSize < kMultipartThreshold) {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            emit objectUploadFailed("Could not open file: " + path);
            return;
        }
        uploadSinglePart(bucketErn, key, file.readAll());
        return;
    }

    beginMultipartUpload(bucketErn, key, path, fileSize);
}

void EsmClient::uploadSinglePart(const QString &bucketErn, const QString &key, const QByteArray &data) {
    QVariantMap headers;
    headers["x-euclid-bucket-ern"] = bucketErn;
    headers["x-euclid-key"] = key;

    m_base->postRaw("esm", "put-object", headers, data,
         [this, bucketErn, key](const QJsonObject &response) {
             emit objectUploaded(bucketErn, key);
             emit objectsReload(bucketErn);
         },
         [this](const QString &message) {
             emit objectUploadFailed(message);
         });
}

void EsmClient::beginMultipartUpload(const QString &bucketErn, const QString &key, const QString &path, const qint64 fileSize) {
    QJsonObject body;
    body["bucketErn"] = bucketErn;
    body["key"] = key;

    m_base->post("esm", "create-upload", body, true,
         [this, bucketErn, key, path, fileSize](const QJsonObject &response) {
             uploadNextPart(bucketErn, key, path, fileSize, response.value("uploadId").toString(), 1, 0);
         },
         [this](const QString &message) {
             emit objectUploadFailed(message);
         });
}

void EsmClient::uploadNextPart(const QString &bucketErn, const QString &key, const QString &path, const qint64 fileSize,
                                const QString &uploadId, const long partNumber, const qint64 bytesSent) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || !file.seek(bytesSent)) {
        emit objectUploadFailed("Could not read file to upload part " + QString::number(partNumber));
        return;
    }
    const QByteArray chunk = file.read(kMultipartThreshold);
    file.close();

    if (chunk.isEmpty()) {
        completeMultipartUpload(bucketErn, key, uploadId);
        return;
    }

    QVariantMap headers;
    headers["x-euclid-upload-id"] = uploadId;
    headers["x-euclid-part-number"] = QString::number(partNumber);

    const qint64 newBytesSent = bytesSent + chunk.size();
    m_base->postRaw("esm", "upload-part", headers, chunk,
         [this, bucketErn, key, path, fileSize, uploadId, partNumber, newBytesSent](const QJsonObject &response) {
             emit uploadProgress(bucketErn, key, newBytesSent, fileSize);
             uploadNextPart(bucketErn, key, path, fileSize, uploadId, partNumber + 1, newBytesSent);
         },
         [this](const QString &message) {
             emit objectUploadFailed(message);
         });
}

void EsmClient::completeMultipartUpload(const QString &bucketErn, const QString &key, const QString &uploadId) {
    QJsonObject body;
    body["uploadId"] = uploadId;

    // complete-upload returns as soon as every part is in, but assembly/hashing/content-type
    // detection for a large file runs afterwards in a detached thread server-side (see
    // EsmServer::handleCompleteUpload) - the object can still be at status UPLOADED with no size/
    // content type in the reload right below. The page's own auto-refresh timer (AppSettings.
    // autoRefreshSeconds) picks up the COMPLETED row on its next tick, so there's no need to chase
    // it with extra delayed reloads here.
    m_base->post("esm", "complete-upload", body, true,
         [this, bucketErn, key](const QJsonObject &response) {
             emit objectUploaded(bucketErn, key);
             emit objectsReload(bucketErn);
         },
         [this](const QString &message) {
             emit objectUploadFailed(message);
         });
}
