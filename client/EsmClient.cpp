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

void EsmClient::fetchObjects(const QString &bucketErn, const QString &prefix, const int pageIndex, const int pageSize, const QString &sortColumn, const QString &sortDirection) {
    QJsonObject body;
    body["bucketErn"] = bucketErn;
    body["prefix"] = prefix;
    body["pageSize"] = pageSize;
    body["pageIndex"] = pageIndex;
    body["sortColumn"] = sortColumn;
    body["sortDirection"] = sortDirection;

    m_base->post("esm", "list-objects", body, true,
         [this, bucketErn](const QJsonObject &response) {
             QVariantList objects;
             for (const QJsonArray array = response.value("objects").toArray(); const auto &value : array) {
                 const QJsonObject object = value.toObject();
                 QVariantMap entry;
                 entry["key"] = object.value("key").toString();
                 entry["ern"] = object.value("ern").toString();
                 entry["bucketErn"] = object.value("bucketErn").toString();
                 entry["size"] = object.value("size").toInteger();
                 entry["status"] = object.value("status").toString();
                 entry["contentType"] = object.value("contentType").toString();
                 entry["md5Sum"] = object.value("md5Sum").toString();
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
