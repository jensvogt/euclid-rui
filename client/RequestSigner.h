#pragma once

#include <QByteArray>
#include <QMap>
#include <QString>

// Signs a euclid gateway request with an EAM access key, so requests can authenticate by key
// instead of by the JWT a password login hands out. The gateway accepts three schemes
// (Core::HttpActionServer::Authenticate): an RFC 9421 message signature, a Bearer token, or
// SigV4 - and checks them in that order.
//
// Both signature schemes here mirror euclid's own implementations byte for byte, including the
// two places euclid departs from the specs on purpose:
//
//   - The covered/signed set is fixed, not chosen by the signer. Both Core::SigV4::Verify and
//     Core::HttpSignature::Verify reject a signature that covers anything other than exactly
//     their own list, so that a MITM cannot strip a component from the signature and the header
//     that announces it and still verify.
//   - The x-euclid-* routing headers are part of that set. euclid puts the target service and
//     action in headers where a REST API would put them in the URI, so leaving them unsigned
//     would leave the request's actual destination unprotected.
class RequestSigner {

public:
    // One request, in the form both schemes need it. `headers` holds the request's own headers
    // keyed by lowercase name (x-euclid-*, host, ...); the signer adds its own on top.
    struct Request {
        QString method;
        QString path;
        QString authority;// host[:port], as the Host header carries it
        QMap<QString, QString> headers;
        QByteArray body;
    };

    struct Credentials {
        QString accessKeyId;
        QString secretAccessKey;
        // Only SigV4 scopes a signature to a region and service; RFC 9421 has no equivalent.
        QString region;
        QString service;
    };

    // Both return the headers to add to the request, keyed as they should be sent. Neither
    // touches anything already in `request.headers`: the signature covers those, so changing one
    // afterwards invalidates it.

    // Adds x-amz-date, x-amz-content-sha256 and Authorization.
    static QMap<QString, QString> signSigV4(const Request &request, const Credentials &credentials);

    // Adds Content-Digest, Signature-Input and Signature.
    static QMap<QString, QString> signRfc9421(const Request &request, const Credentials &credentials);

    // Header names SigV4 signs, in the order the canonical request needs them (already
    // alphabetical). Mirrors Core::SigV4::SignedHeaderNames().
    static QStringList sigV4SignedHeaders();

    // Components an RFC 9421 signature covers, in signature-base order. Mirrors
    // Core::HttpSignature::CoveredComponents(). Every one of them must be present and non-empty
    // on the request: the server refuses to build a base over a component it cannot read, rather
    // than treating it as empty.
    static QStringList rfc9421Components();
};
