import Foundation
import Crypto
import X509
import SwiftASN1
import Security

/// Generates the Mac's self-signed TLS identity (U2) using Apple's swift-certificates/swift-crypto,
/// and bridges it to a `SecIdentity` so Network.framework can present it for mutual TLS. The cert
/// fingerprint (SHA-256 of the DER) is the value the peer pins — identical scheme to the Android side.
public struct SelfSignedIdentity {
    public let certificateDER: Data
    public let privateKey: P256.Signing.PrivateKey
    public let fingerprint: String

    public init(certificateDER: Data, privateKey: P256.Signing.PrivateKey) {
        self.certificateDER = certificateDER
        self.privateKey = privateKey
        self.fingerprint = SHA256.hash(data: certificateDER).map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    public static func generate(commonName: String) throws -> SelfSignedIdentity {
        let key = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(key)
        let name = try DistinguishedName { CommonName(commonName) }
        let now = Date()
        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: certKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(3650 * 24 * 3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true)
            },
            issuerPrivateKey: certKey
        )
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        let der = Data(serializer.serializedBytes)
        return SelfSignedIdentity(certificateDER: der, privateKey: key)
    }

    /// Bridge to a `SecIdentity` by importing cert + key into a private, temporary file keychain and
    /// pairing them. A temp keychain avoids the data-protection-keychain entitlement (errSecMissingEntitlement)
    /// that blocks unsigned/ad-hoc binaries from the default keychain.
    public func makeSecIdentity(label: String = "AndroidBridge") throws -> SecIdentity {
        guard let secCert = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw IdentityError.certImport
        }
        let keychain = try makeTempKeychain()

        var format = SecExternalFormat.formatOpenSSL
        var itemType = SecExternalItemType.itemTypePrivateKey
        var imported: CFArray?
        let ks = SecItemImport(privateKey.derRepresentation as CFData, nil, &format, &itemType, [], nil, keychain, &imported)
        guard ks == errSecSuccess else { throw IdentityError.keychainAddKey(ks) }

        let addCert: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecUseKeychain as String: keychain,
            kSecAttrLabel as String: label,
        ]
        let cs = SecItemAdd(addCert as CFDictionary, nil)
        guard cs == errSecSuccess || cs == errSecDuplicateItem else { throw IdentityError.keychainAddCert(cs) }

        var identity: SecIdentity?
        let is0 = SecIdentityCreateWithCertificate(keychain, secCert, &identity)
        guard is0 == errSecSuccess, let id = identity else { throw IdentityError.identityCreate(is0) }
        return id
    }

    private func makeTempKeychain() throws -> SecKeychain {
        let path = NSTemporaryDirectory() + "androidbridge-" + UUID().uuidString + ".keychain"
        let password = UUID().uuidString
        var keychain: SecKeychain?
        let status = password.withCString { pw in
            SecKeychainCreate(path, UInt32(strlen(pw)), pw, false, nil, &keychain)
        }
        guard status == errSecSuccess, let kc = keychain else { throw IdentityError.keychainCreate(status) }
        return kc
    }

    public enum IdentityError: Error {
        case certImport
        case keychainCreate(OSStatus), keychainAddKey(OSStatus), keychainAddCert(OSStatus), identityCreate(OSStatus)
    }
}
