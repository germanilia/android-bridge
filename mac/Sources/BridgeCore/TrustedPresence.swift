import Foundation

/// Trusted Presence: relax the Mac's lock behaviour only while a place the user marked
/// as safe is actually present.
///
/// A place is identified by a hardware address, never by a name:
///  - `.wifi` stores the MAC address of the router the Mac is talking to. macOS 14+ hides
///    Wi-Fi network names from ordinary code (CoreWLAN returns nil without Location access
///    and `ipconfig getsummary` returns the literal text `<redacted>`), and a network name
///    is trivial to fake anyway. The router's address needs no permission to read.
///  - `.bluetooth` stores a paired device's Bluetooth address, and counts only while that
///    device is actually connected.
///
/// Everything in this file is pure so the decision is testable without hardware.
/// Reading the world lives in `PresenceSensor`; acting on the decision lives in
/// `ScreenLockControl` and `TrustedPresenceController`.

public struct TrustedPlace: Codable, Equatable, Identifiable, Hashable {
    public enum Kind: String, Codable, Hashable {
        case wifi
        case bluetooth
    }

    public let kind: Kind
    /// Hardware address, stored exactly as the user's system reported it. Compared normalized.
    public let identifier: String
    /// Human-friendly name, shown in the UI only. Never used for matching.
    public var label: String

    public var id: String { "\(kind.rawValue):\(TrustedPresence.normalize(identifier))" }

    public init(kind: Kind, identifier: String, label: String) {
        self.kind = kind
        self.identifier = identifier
        self.label = label
    }
}

/// What the Mac can see right now.
public struct PresenceSnapshot: Equatable {
    public let wifiRouterAddress: String?
    public let connectedBluetoothAddresses: [String]

    public init(wifiRouterAddress: String?, connectedBluetoothAddresses: [String]) {
        self.wifiRouterAddress = wifiRouterAddress
        self.connectedBluetoothAddresses = connectedBluetoothAddresses
    }
}

public struct TrustedPresenceSettings: Codable, Equatable {
    /// Hold the Mac awake so the screen never locks in the first place.
    public var keepAwake: Bool
    /// Turn off the "type your password to wake" prompt via `sysadminctl -screenLock`.
    public var disableLockPassword: Bool
    /// Restore the password prompt whenever the Mac sleeps, so a Mac that slept at home
    /// cannot be opened without a password somewhere else. Costs one password entry on wake.
    public var relockOnSleep: Bool
    public var places: [TrustedPlace]

    /// Both behaviours off and nothing trusted. A fresh install never weakens the Mac by itself.
    public static let disabled = TrustedPresenceSettings(
        keepAwake: false, disableLockPassword: false, relockOnSleep: true, places: []
    )

    public init(keepAwake: Bool, disableLockPassword: Bool, relockOnSleep: Bool = true, places: [TrustedPlace]) {
        self.keepAwake = keepAwake
        self.disableLockPassword = disableLockPassword
        self.relockOnSleep = relockOnSleep
        self.places = places
    }

    /// Settings saved before `relockOnSleep` existed decode as the safe value, not `false`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keepAwake = try container.decode(Bool.self, forKey: .keepAwake)
        disableLockPassword = try container.decode(Bool.self, forKey: .disableLockPassword)
        relockOnSleep = try container.decodeIfPresent(Bool.self, forKey: .relockOnSleep) ?? true
        places = try container.decode([TrustedPlace].self, forKey: .places)
    }
}

/// The two things the controller should make true right now.
public enum LockAction: Equatable {
    /// Turn the wake-password prompt off.
    case disable
    /// Put the wake-password prompt back, because this app was the one that removed it.
    case restore
}

public struct PresencePlan: Equatable {
    public let holdAwake: Bool
    public let requireLockPassword: Bool
}

public enum TrustedPresence {

    /// Canonical form of a hardware address: lowercase, colon-separated, zero-padded octets.
    /// `arp` prints unpadded octets and IOBluetooth prints dashes and uppercase, so every
    /// address is funnelled through here before it is compared.
    public static func normalize(_ address: String) -> String {
        address
            .replacingOccurrences(of: "-", with: ":")
            .lowercased()
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.count == 1 ? "0" + $0 : String($0) }
            .joined(separator: ":")
    }

    /// Which of the user's trusted places are present in this snapshot.
    /// Wi-Fi and Bluetooth addresses never satisfy each other, even if the strings match.
    public static func present(in snapshot: PresenceSnapshot, trusted: [TrustedPlace]) -> [TrustedPlace] {
        let router = snapshot.wifiRouterAddress.map(normalize)
        let bluetooth = Set(snapshot.connectedBluetoothAddresses.map(normalize))
        return trusted.filter { place in
            switch place.kind {
            case .wifi: return normalize(place.identifier) == router
            case .bluetooth: return bluetooth.contains(normalize(place.identifier))
            }
        }
    }

    /// A switch that is off leaves its behaviour completely alone, trusted or not.
    public static func plan(settings: TrustedPresenceSettings, isTrusted: Bool) -> PresencePlan {
        PresencePlan(
            holdAwake: settings.keepAwake && isTrusted,
            requireLockPassword: !(settings.disableLockPassword && isTrusted)
        )
    }

    /// What to make true as the Mac goes to sleep. A sleeping Mac is never held awake,
    /// and by default it always wakes asking for a password.
    public static func planForSleep(settings: TrustedPresenceSettings) -> PresencePlan {
        PresencePlan(holdAwake: false, requireLockPassword: settings.relockOnSleep)
    }

    /// True only when at least one trusted place is a Bluetooth device. Gates the
    /// privacy-sensitive pairing-list read, and therefore the Bluetooth permission prompt.
    public static func needsBluetooth(places: [TrustedPlace]) -> Bool {
        places.contains { $0.kind == .bluetooth }
    }

    /// Whether to change the wake-password setting, and in which direction.
    ///
    /// `appDisabledIt` is the app remembering that it, not the user, turned the prompt off.
    /// Without it the app would either strand the Mac unlocked (when the feature is switched
    /// off while the prompt is down) or trample a prompt the user disabled in System Settings.
    public static func lockAction(
        plan: PresencePlan,
        featureEnabled: Bool,
        currentlyRequiresPassword: Bool,
        appDisabledIt: Bool
    ) -> LockAction? {
        guard currentlyRequiresPassword != plan.requireLockPassword else { return nil }
        if plan.requireLockPassword { return appDisabledIt ? .restore : nil }
        return featureEnabled ? .disable : nil
    }

    /// What to make true as the app quits, so quitting can never leave the Mac unlocked.
    public static func planForShutdown() -> PresencePlan {
        PresencePlan(holdAwake: false, requireLockPassword: true)
    }
}

/// Settings live in UserDefaults, not the Keychain — none of this is secret.
/// The login password used to drive `sysadminctl` is the only secret, and it lives in
/// `LoginPasswordStore`.
public final class TrustedPresenceStore {
    private static let key = "trustedPresence.settings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> TrustedPresenceSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(TrustedPresenceSettings.self, from: data)
        else { return .disabled }
        return settings
    }

    public func save(_ settings: TrustedPresenceSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
