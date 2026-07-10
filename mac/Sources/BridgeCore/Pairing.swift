import Foundation
import CryptoKit
import DeviceLinkProtocol

public struct DeviceIdentity: Codable, Equatable {
    public let deviceId: String
    public let deviceName: String
    public let publicKeyB64: String
}

public struct PairedDevice: Codable, Equatable {
    public let deviceId: String
    public let deviceName: String
    public let publicKeyB64: String
    public let fingerprint: String
    public var host: String = ""
    public var port: Int = 0
}

public struct QrPayload: Codable, Equatable {
    public let deviceId: String
    public let deviceName: String
    public let publicKeyB64: String
    public let fingerprint: String
    public let host: String
    public let port: Int
}

/// Pairing & trust (U2). EC P-256 via CryptoKit; trust-on-first-use cert pinning recorded in SecureStore.
public final class PairingManager {
    private let store: SecureStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(store: SecureStore) { self.store = store }

    public func fingerprint(of publicKeyB64: String) -> String {
        guard let data = Data(base64Encoded: publicKeyB64) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    public func generateIdentity(_ deviceName: String) -> DeviceIdentity {
        let priv = P256.Signing.PrivateKey()
        let pubB64 = priv.publicKey.rawRepresentation.base64EncodedString()
        let identity = DeviceIdentity(deviceId: UUID().uuidString, deviceName: deviceName, publicKeyB64: pubB64)
        store.put(Keys.identity, (try? String(data: encoder.encode(identity), encoding: .utf8)) ?? "")
        store.put(Keys.privateKey, priv.rawRepresentation.base64EncodedString())
        return identity
    }

    public func loadIdentity() -> DeviceIdentity? {
        guard let s = store.get(Keys.identity), let d = s.data(using: .utf8) else { return nil }
        return try? decoder.decode(DeviceIdentity.self, from: d)
    }

    public func createPairingQr(_ identity: DeviceIdentity, host: String, port: Int) -> String {
        let payload = QrPayload(
            deviceId: identity.deviceId, deviceName: identity.deviceName,
            publicKeyB64: identity.publicKeyB64, fingerprint: fingerprint(of: identity.publicKeyB64),
            host: host, port: port
        )
        return (try? String(data: encoder.encode(payload), encoding: .utf8)) ?? ""
    }

    public enum PairingError: Error, Equatable { case malformed, fingerprintMismatch }

    @discardableResult
    public func consumePairingQr(_ qr: String) throws -> PairedDevice {
        guard let data = qr.data(using: .utf8), let payload = try? decoder.decode(QrPayload.self, from: data) else {
            throw PairingError.malformed
        }
        if fingerprint(of: payload.publicKeyB64) != payload.fingerprint {
            LinkLogger.securityEvent("pair_fingerprint_mismatch", ["deviceId": payload.deviceId])
            throw PairingError.fingerprintMismatch
        }
        let peer = PairedDevice(
            deviceId: payload.deviceId, deviceName: payload.deviceName, publicKeyB64: payload.publicKeyB64,
            fingerprint: payload.fingerprint, host: payload.host, port: payload.port
        )
        pin(peer)
        return peer
    }

    public func pin(_ peer: PairedDevice) {
        let list = listPaired().filter { $0.deviceId != peer.deviceId } + [peer]
        savePaired(list)
        LinkLogger.info("peer_pinned", ["deviceId": peer.deviceId])
    }

    public func listPaired() -> [PairedDevice] {
        guard let s = store.get(Keys.paired), let d = s.data(using: .utf8) else { return [] }
        return (try? decoder.decode([PairedDevice].self, from: d)) ?? []
    }

    public func unpair(_ deviceId: String) {
        savePaired(listPaired().filter { $0.deviceId != deviceId })
        LinkLogger.info("peer_unpaired", ["deviceId": deviceId])
    }

    public func isPinned(_ fingerprint: String) -> Bool { listPaired().contains { $0.fingerprint == fingerprint } }

    private func savePaired(_ list: [PairedDevice]) {
        store.put(Keys.paired, (try? String(data: encoder.encode(list), encoding: .utf8)) ?? "[]")
    }

    private enum Keys {
        static let identity = "identity"
        static let privateKey = "identity.private"
        static let paired = "paired.devices"
    }
}
