import Foundation
import IOBluetooth

/// Reads what the Mac can currently see, for `TrustedPresence` to judge.
/// Nothing here decides anything; the decision is pure and lives in `TrustedPresence`.
public enum PresenceSensor {

    /// MAC address of the Wi-Fi router this Mac is talking to, or nil when not on Wi-Fi.
    ///
    /// Deliberately not CoreWLAN's `bssid()`: since macOS 14 that returns nil unless the
    /// caller holds Location authorization, and it stays nil if the user declines. The
    /// router's address comes from DHCP + the ARP table, which need no permission at all,
    /// and identifies the same physical access point.
    public static func wifiRouterAddress(interface: String = "en0") -> String? {
        guard let routerIP = shell("/usr/sbin/ipconfig", ["getsummary", interface])?
            .split(separator: "\n")
            .compactMap({ line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Router" else { return nil }
                return parts[1].trimmingCharacters(in: .whitespaces)
            })
            .first
        else { return nil }

        // The router may have aged out of the ARP cache; one ping repopulates it.
        _ = shell("/sbin/ping", ["-c", "1", "-t", "1", routerIP])

        guard let arp = shell("/usr/sbin/arp", ["-n", routerIP]),
              let range = arp.range(of: #"(?<= at )[0-9a-fA-F:]+(?= on )"#, options: .regularExpression)
        else { return nil }
        return TrustedPresence.normalize(String(arp[range]))
    }

    /// Bluetooth addresses that are connected right now. Needs no permission.
    /// Call on the main thread — IOBluetooth is not thread-safe.
    public static func connectedBluetoothAddresses() -> [String] {
        pairedBluetoothDevices().filter(\.isConnected).map(\.address)
    }

    public struct BluetoothDevice: Identifiable, Equatable {
        public let address: String
        public let name: String
        public let isConnected: Bool
        public var id: String { address }
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

    /// Reading the Bluetooth pairing list is privacy-gated: macOS terminates the app unless
    /// `NSBluetoothAlwaysUsageDescription` is in Info.plist, and prompts the user the first
    /// time. So it is read only when the user actually has a trusted Bluetooth device —
    /// nobody gets a Bluetooth prompt for a feature they are not using.
    public static func snapshot(includeBluetooth: Bool) -> PresenceSnapshot {
        PresenceSnapshot(
            wifiRouterAddress: wifiRouterAddress(),
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
