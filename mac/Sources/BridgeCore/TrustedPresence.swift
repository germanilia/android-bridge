import Foundation

/// Trusted Presence: relax the Mac's lock behaviour only while a place the user marked
/// as safe is actually present.
///
/// A place is identified by a hardware address, never by a name:
///  - `.wifi` stores a network NAME (SSID), so the user can pick from every network this Mac
///    remembers without having to visit each one, and so one entry covers a whole mesh.
///    Reading the current network's name needs Location authorization — macOS returns the
///    literal text `<redacted>` otherwise. Names are matched exactly and are case-sensitive.
///    A name is easy to impersonate, so this is convenience, not authentication.
///  - `.bluetooth` stores a paired device's Bluetooth address, and counts only while that
///    device is actually connected. Addresses are normalized before comparison.
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
    /// A network name for `.wifi`, a Bluetooth address for `.bluetooth`.
    public let identifier: String
    /// Human-friendly name, shown in the UI only. Never used for matching.
    public var label: String

    public var id: String { "\(kind.rawValue):\(TrustedPresence.comparable(kind: kind, identifier))" }

    public init(kind: Kind, identifier: String, label: String) {
        self.kind = kind
        self.identifier = identifier
        self.label = label
    }
}

/// What the Mac can see right now.
public struct PresenceSnapshot: Equatable {
    /// Name of the Wi-Fi network this Mac is on. Nil when off Wi-Fi, or when macOS withheld
    /// it because Location access has not been granted.
    public let wifiSSID: String?
    public let connectedBluetoothAddresses: [String]

    public init(wifiSSID: String?, connectedBluetoothAddresses: [String]) {
        self.wifiSSID = wifiSSID
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

    /// How an identifier is compared, which depends on what it is. A Bluetooth address is
    /// normalized so `64-B5-F2-...` and `64:b5:f2:...` are the same device; a network name is
    /// left exactly as typed, because names are case-sensitive and may contain `:` or `-`.
    public static func comparable(kind: TrustedPlace.Kind, _ identifier: String) -> String {
        switch kind {
        case .wifi: return identifier
        case .bluetooth: return normalize(identifier)
        }
    }

    /// Which of the user's trusted places are present in this snapshot.
    /// A Wi-Fi entry and a Bluetooth entry never satisfy each other, even if the strings match.
    public static func present(in snapshot: PresenceSnapshot, trusted: [TrustedPlace]) -> [TrustedPlace] {
        let bluetooth = Set(snapshot.connectedBluetoothAddresses.map { comparable(kind: .bluetooth, $0) })
        return trusted.filter { place in
            switch place.kind {
            case .wifi:
                guard let ssid = snapshot.wifiSSID else { return false }
                return comparable(kind: .wifi, place.identifier) == comparable(kind: .wifi, ssid)
            case .bluetooth:
                return bluetooth.contains(comparable(kind: .bluetooth, place.identifier))
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

    /// Upgrades settings written by the build that identified Wi-Fi networks by their
    /// router's MAC address. Such an entry can never match name-based comparison, so it is
    /// rewritten to the network name the user gave it, or dropped when the label carries no
    /// name to recover. Dropping beats keeping: a place that cannot match must not sit in the
    /// list looking as though it still works.
    public static func migrate(places: [TrustedPlace]) -> [TrustedPlace] {
        places.compactMap { place in
            guard place.kind == .wifi, looksLikeHardwareAddress(place.identifier) else { return place }
            // The old UI auto-labelled an unnamed network exactly "Wi-Fi <last 5 of address>".
            // That label, the address itself, and an empty label all carry no network name.
            let autoLabel = "Wi-Fi " + place.identifier.suffix(5)
            let carriesNoName = place.label.isEmpty
                || place.label == autoLabel
                || looksLikeHardwareAddress(place.label)
            return carriesNoName ? nil : TrustedPlace(kind: .wifi, identifier: place.label, label: place.label)
        }
    }

    /// Six colon- or dash-separated hex groups, i.e. `d4:35:1d:4f:c1:8d`.
    static func looksLikeHardwareAddress(_ value: String) -> Bool {
        let groups = value.replacingOccurrences(of: "-", with: ":").split(separator: ":")
        return groups.count == 6 && groups.allSatisfy { $0.count <= 2 && $0.allSatisfy(\.isHexDigit) }
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
              var settings = try? JSONDecoder().decode(TrustedPresenceSettings.self, from: data)
        else { return .disabled }
        let migrated = TrustedPresence.migrate(places: settings.places)
        if migrated != settings.places {
            // Write the upgrade back once, so the stored settings match what is in use
            // rather than quietly differing from it on every load.
            settings.places = migrated
            save(settings)
        }
        return settings
    }

    public func save(_ settings: TrustedPresenceSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
