import Foundation
import CoreWLAN
import CoreLocation
import IOBluetooth

/// Reads what the Mac can currently see, for `TrustedPresence` to judge.
/// Nothing here decides anything; the decision is pure and lives in `TrustedPresence`.
public enum PresenceSensor {

    // MARK: - Wi-Fi

    /// Name of the Wi-Fi network this Mac is on.
    ///
    /// Since macOS 14 this is withheld unless the app holds Location authorization —
    /// CoreWLAN returns nil and `ipconfig getsummary` returns the literal text `<redacted>`.
    /// `LocationAccess` handles asking for it.
    public static func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    /// Every Wi-Fi network this Mac remembers, newest first, for the picker.
    /// Needs no permission at all, which is why the picker works before Location is granted.
    public static func rememberedNetworks(interface: String = "en0") -> [String] {
        guard let output = shell("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", interface]) else { return [] }
        // First line is the "Preferred networks on en0:" header; the rest are tab-indented names.
        return output
            .split(separator: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Bluetooth

    public struct BluetoothDevice: Identifiable, Equatable {
        public let address: String
        public let name: String
        public let isConnected: Bool
        public var id: String { address }
    }

    /// Bluetooth addresses that are connected right now.
    /// Call on the main thread — IOBluetooth is not thread-safe.
    public static func connectedBluetoothAddresses() -> [String] {
        pairedBluetoothDevices().filter(\.isConnected).map(\.address)
    }

    /// Every device paired to this Mac, for the picker. Call on the main thread.
    public static func pairedBluetoothDevices() -> [BluetoothDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var seen = Set<String>()
        return paired.compactMap { device -> BluetoothDevice? in
            guard let address = device.addressString else { return nil }
            let normalized = TrustedPresence.normalize(address)
            guard seen.insert(normalized).inserted else { return nil }  // macOS lists some devices twice
            return BluetoothDevice(
                address: normalized,
                name: device.name ?? normalized,
                isConnected: device.isConnected()
            )
        }
        .sorted { ($0.isConnected ? 0 : 1, $0.name.lowercased()) < ($1.isConnected ? 0 : 1, $1.name.lowercased()) }
    }

    // MARK: -

    /// Reading the Bluetooth pairing list is privacy-gated: macOS terminates the app unless
    /// `NSBluetoothAlwaysUsageDescription` is in Info.plist, and prompts the user the first
    /// time. So it is read only when the user actually has a trusted Bluetooth device —
    /// nobody gets a Bluetooth prompt for a feature they are not using.
    public static func snapshot(includeBluetooth: Bool) -> PresenceSnapshot {
        PresenceSnapshot(
            wifiSSID: currentSSID(),
            connectedBluetoothAddresses: includeBluetooth ? connectedBluetoothAddresses() : []
        )
    }

    private static func shell(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        // Read before waiting: these commands are tiny, but a full pipe buffer would deadlock.
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Location Services is the gate on reading the current Wi-Fi network's name. macOS ties
/// SSID access to it because knowing which network you are on reveals where you are.
/// Nothing else in Android Bridge uses your location, and no location is ever stored or sent.
public final class LocationAccess: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    public override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// macOS has no "when in use" state — `requestWhenInUseAuthorization()` resolves to
    /// `.authorizedAlways` here, and `.authorizedWhenInUse` is unavailable on this platform.
    public var isAuthorized: Bool {
        status == .authorizedAlways
    }

    /// Shows the system prompt the first time. Once the user has answered, macOS never asks
    /// again — after a denial the only way back is System Settings.
    public func request() {
        manager.requestWhenInUseAuthorization()
    }

    public var explanation: String {
        switch status {
        case .notDetermined:
            return "Android Bridge needs Location access to see which Wi-Fi network you are on. macOS ties the network name to Location. Nothing about your location is stored or sent anywhere."
        case .denied, .restricted:
            return "Location access is off, so macOS hides the Wi-Fi network name and no Wi-Fi network can match. Turn it on in System Settings ▸ Privacy & Security ▸ Location Services ▸ Android Bridge."
        case .authorizedAlways:
            return ""
        @unknown default:
            return "macOS reported an unfamiliar Location setting, so the Wi-Fi network name may not be readable. Check System Settings ▸ Privacy & Security ▸ Location Services ▸ Android Bridge."
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
