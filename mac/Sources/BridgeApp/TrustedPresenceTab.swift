import SwiftUI
import BridgeCore

/// "Trusted Presence" tab: pick the Wi-Fi networks and Bluetooth devices that mean
/// "I am somewhere safe", and choose what the Mac should relax while one is present.
struct TrustedPresenceTab: View {
    @ObservedObject var presence: TrustedPresenceController
    @State private var newWifiLabel = ""
    @State private var loginPassword = ""
    @State private var hasSavedPassword = false
    @State private var passwordError: String?
    /// Loaded on request, never in `body`: reading the pairing list asks macOS for
    /// Bluetooth permission, and that must be something the user chose to do.
    @State private var pairedDevices: [PresenceSensor.BluetoothDevice] = []
    @State private var didLoadDevices = false

    private var trustedWifi: [TrustedPlace] { presence.settings.places.filter { $0.kind == .wifi } }
    private var trustedBluetooth: [TrustedPlace] { presence.settings.places.filter { $0.kind == .bluetooth } }

    var body: some View {
        Form {
            statusSection
            behaviourSection
            if presence.settings.disableLockPassword { loginPasswordSection }
            wifiSection
            bluetoothSection
        }
        .formStyle(.grouped)
        .onAppear {
            hasSavedPassword = presence.passwords.exists
            presence.refresh()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            LabeledContent("Right now") {
                if presence.isTrusted {
                    Label(presence.matched.map(\.label).joined(separator: ", "), systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not somewhere trusted", systemImage: "shield.slash")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Wake password", value: presence.passwordRequired ? "Required" : "Not required")
            LabeledContent("Keeping Mac awake", value: presence.isHoldingAwake ? "Yes" : "No")
            if let error = presence.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Button("Check now") { presence.refresh() }
        } header: {
            Text("Status")
        } footer: {
            Text("Checked every 20 seconds, and immediately when the Mac wakes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - The two switches

    private var behaviourSection: some View {
        Section {
            Toggle("Keep the Mac awake", isOn: $presence.settings.keepAwake)
            Text("The screen never idles, so it never reaches the lock screen. Closing the lid still sleeps and still locks. Costs battery and can burn in the display.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle("Turn off the wake password", isOn: $presence.settings.disableLockPassword)
            Text("The screen still sleeps and locks, but waking it does not ask for a password. Needs your login password saved below, because macOS refuses to change this setting without it.")
                .font(.caption).foregroundStyle(.secondary)

            if presence.settings.disableLockPassword {
                Toggle("Put the password back whenever the Mac sleeps", isOn: $presence.settings.relockOnSleep)
                Text("Strongly recommended. Without it, a Mac that slept at home opens with no password anywhere else — in a bag, in an office, at a café. Leaving it on costs one password entry after each sleep.")
                    .font(.caption).foregroundStyle(presence.settings.relockOnSleep ? Color.secondary : Color.orange)
            }
        } header: {
            Text("While somewhere trusted")
        }
    }

    // MARK: - Login password

    private var loginPasswordSection: some View {
        Section {
            if hasSavedPassword {
                LabeledContent("Login password", value: "Saved in your Keychain")
                Button("Remove saved password", role: .destructive) { removePassword() }
            } else {
                SecureField("Your macOS login password", text: $loginPassword)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save password") { savePassword() }
                        .disabled(loginPassword.isEmpty)
                }
                if let passwordError {
                    Label(passwordError, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
        } header: {
            Text("Login password")
        } footer: {
            Text("Android Bridge stores this in your login Keychain and passes it to `sysadminctl` on stdin, so it never appears in the process list. Anything that can read your Keychain can read it — that is a real trade-off for the convenience.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func savePassword() {
        guard ScreenLockControl.verify(password: loginPassword) else {
            passwordError = "macOS rejected that password."
            return
        }
        do {
            try presence.passwords.write(loginPassword)
            loginPassword = ""
            hasSavedPassword = true
            passwordError = nil
            presence.refresh()
        } catch {
            passwordError = error.localizedDescription
        }
    }

    private func removePassword() {
        do {
            try presence.passwords.delete()
            hasSavedPassword = false
            presence.settings.disableLockPassword = false
        } catch {
            passwordError = error.localizedDescription
        }
    }

    // MARK: - Wi-Fi

    private var wifiSection: some View {
        Section {
            ForEach(trustedWifi) { place in
                HStack {
                    Label(place.label, systemImage: "wifi")
                    Text(place.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    if presence.matched.contains(place) {
                        Label("Here", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.green)
                    }
                    Button("Remove", role: .destructive) { presence.remove(place) }
                }
            }
            if let current = presence.snapshot.wifiRouterAddress {
                HStack {
                    TextField("Name this network (e.g. Home)", text: $newWifiLabel)
                        .textFieldStyle(.roundedBorder)
                    Button("Trust this network") {
                        presence.trustCurrentWifi(label: newWifiLabel.isEmpty ? "Wi-Fi \(current.suffix(5))" : newWifiLabel)
                        newWifiLabel = ""
                    }
                }
                Text("Currently connected through router \(current)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not on Wi-Fi right now.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Trusted Wi-Fi")
        } footer: {
            Text("A network is remembered by its router's hardware address, not its name — macOS hides Wi-Fi names from apps without Location access, and names are easy to fake. A mesh router gives each access point its own address, so add each one you actually use. Hardware addresses can still be copied by someone who knows yours.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Bluetooth

    private var bluetoothSection: some View {
        Section {
            if !didLoadDevices {
                Button("Show paired Bluetooth devices") {
                    pairedDevices = PresenceSensor.pairedBluetoothDevices()
                    didLoadDevices = true
                }
                Text("macOS will ask for Bluetooth permission the first time. Skip this if you only want to use Wi-Fi.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(pairedDevices) { device in
                let place = TrustedPlace(kind: .bluetooth, identifier: device.address, label: device.name)
                let trusted = trustedBluetooth.contains { $0.id == place.id }
                HStack {
                    Label(device.name, systemImage: device.isConnected ? "dot.radiowaves.left.and.right" : "circle.dashed")
                        .foregroundStyle(device.isConnected ? Color.primary : Color.secondary)
                    Spacer()
                    Toggle("Trusted", isOn: Binding(
                        get: { trusted },
                        set: { $0 ? presence.add(place) : presence.remove(place) }
                    ))
                    .labelsHidden()
                }
            }
            if !didLoadDevices {
                ForEach(trustedBluetooth) { place in
                    HStack {
                        Label(place.label, systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Button("Remove", role: .destructive) { presence.remove(place) }
                    }
                }
            }
            if didLoadDevices {
                Button("Refresh list") { pairedDevices = PresenceSensor.pairedBluetoothDevices() }
            }
        } header: {
            Text("Trusted Bluetooth devices")
        } footer: {
            Text("Counts only while the device is actually connected. A Bluetooth address is not proof of identity — treat this as convenience, not security.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
