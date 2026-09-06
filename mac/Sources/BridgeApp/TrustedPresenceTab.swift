import SwiftUI
import BridgeCore

/// "Trusted Presence" tab: pick the Wi-Fi networks and Bluetooth devices that mean
/// "I am somewhere safe", and choose what the Mac should relax while one is present.
struct TrustedPresenceTab: View {
    @ObservedObject var presence: TrustedPresenceController
    @State private var loginPassword = ""
    @State private var hasSavedPassword = false
    @State private var passwordError: String?
    /// Loaded on request, never in `body`: reading the pairing list asks macOS for
    /// Bluetooth permission, and that must be something the user chose to do.
    @State private var pairedDevices: [PresenceSensor.BluetoothDevice] = []
    @State private var didLoadDevices = false
    @State private var rememberedNetworks: [String] = []
    @State private var networkSearch = ""

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
            LabeledContent("Wake password") {
                Text(presence.passwordRequired ? "Required" : "Not required")
                    .foregroundStyle(presence.passwordRequired ? Color.secondary : Color.orange)
            }
            if !presence.passwordRequired && !presence.settings.relockOnSleep {
                Label("Right now this Mac wakes without asking for a password, and will keep doing so even if you sleep it and carry it somewhere else.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
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

            Toggle("Turn off the wake password", isOn: $presence.settings.disableLockPassword)
            Text("The screen still sleeps and locks, but waking it does not ask for a password. Needs your login password saved below, because macOS refuses to change this setting without it.")
                .font(.caption).foregroundStyle(.secondary)

            if presence.settings.disableLockPassword {
                Toggle("Ask for the password again after the Mac sleeps", isOn: $presence.settings.relockOnSleep)
                if presence.settings.relockOnSleep {
                    Text("On. Sleeping your Mac brings the password back, so you type it once on the next wake and it switches off again while you are somewhere trusted. This is what stops a Mac that fell asleep at home from being opened by anyone who picks it up elsewhere.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Off. Your Mac can be opened without a password anywhere, including after it sleeps in a bag on the way out of the house. It only asks again once you leave every trusted network — which will not have happened yet if it was asleep.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
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

    /// The network you are on first, then the ones you trust, then everything else by name.
    /// This Mac remembers 100+ networks, so saved order is unusable.
    private var visibleNetworks: [String] {
        let trusted = Set(trustedWifi.map(\.identifier))
        let query = networkSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return rememberedNetworks
            .filter { query.isEmpty || $0.lowercased().contains(query) }
            .sorted { a, b in
                func rank(_ name: String) -> Int {
                    if name == presence.snapshot.wifiSSID { return 0 }
                    if trusted.contains(name) { return 1 }
                    return 2
                }
                return rank(a) == rank(b)
                    ? a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                    : rank(a) < rank(b)
            }
    }

    private var wifiSection: some View {
        Section {
            if !presence.location.isAuthorized {
                Text(presence.location.explanation).font(.caption).foregroundStyle(.orange)
                if presence.location.status == .notDetermined {
                    Button("Allow Location access") { presence.location.request() }
                } else {
                    Button("Open Location Services settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                    }
                }
            }
            TextField("Search \(rememberedNetworks.count) networks", text: $networkSearch)
                .textFieldStyle(.roundedBorder)
            // 100+ remembered networks would make the tab scroll forever, so the list
            // gets its own fixed-height scroll area and the page stays a readable length.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleNetworks, id: \.self) { name in
                        let place = TrustedPlace(kind: .wifi, identifier: name, label: name)
                        HStack {
                            Label(name, systemImage: "wifi")
                            if name == presence.snapshot.wifiSSID {
                                Text("here now").font(.caption).foregroundStyle(.green)
                            }
                            Spacer()
                            Toggle("Trusted", isOn: Binding(
                                get: { trustedWifi.contains { $0.id == place.id } },
                                set: { $0 ? presence.add(place) : presence.remove(place) }
                            ))
                            .labelsHidden()
                        }
                    }
                    if visibleNetworks.isEmpty {
                        Text("No remembered network matches \"\(networkSearch)\".")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(height: 260)
            // A trusted network the Mac no longer remembers still needs a way off the list.
            ForEach(trustedWifi.filter { !rememberedNetworks.contains($0.identifier) }) { place in
                HStack {
                    Label(place.label, systemImage: "wifi.exclamationmark")
                    Text("not in this Mac's remembered networks").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) { presence.remove(place) }
                }
            }
            HStack {
                Text("\(trustedWifi.count) trusted of \(rememberedNetworks.count) remembered")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh list") { rememberedNetworks = PresenceSensor.rememberedNetworks() }
            }
        } header: {
            Text("Trusted Wi-Fi")
        } footer: {
            Text("Every network this Mac remembers. Turn on as many as you like — you do not have to be connected to add one, and one entry covers every access point of a mesh. Networks are matched by name, and a name is easy to impersonate: someone can broadcast a hotspot called \"fox5\" and this Mac will trust it. Convenience, not security.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Bluetooth

    private var bluetoothSection: some View {
        Section {
            if didLoadDevices {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(pairedDevices) { device in
                            let place = TrustedPlace(kind: .bluetooth, identifier: device.address, label: device.name)
                            HStack {
                                Label(device.name, systemImage: device.isConnected ? "dot.radiowaves.left.and.right" : "circle.dashed")
                                    .foregroundStyle(device.isConnected ? Color.primary : Color.secondary)
                                if device.isConnected {
                                    Text("connected").font(.caption).foregroundStyle(.green)
                                }
                                Spacer()
                                Toggle("Trusted", isOn: Binding(
                                    get: { trustedBluetooth.contains { $0.id == place.id } },
                                    set: { $0 ? presence.add(place) : presence.remove(place) }
                                ))
                                .labelsHidden()
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 220)
                HStack {
                    Text("\(trustedBluetooth.count) trusted of \(pairedDevices.count) paired")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh list") { pairedDevices = PresenceSensor.pairedBluetoothDevices() }
                }
            } else {
                Button("Show paired Bluetooth devices") {
                    pairedDevices = PresenceSensor.pairedBluetoothDevices()
                    didLoadDevices = true
                }
                Text("macOS will ask for Bluetooth permission the first time. Skip this if you only want to use Wi-Fi.")
                    .font(.caption).foregroundStyle(.secondary)
                // Already-trusted devices stay visible and removable before the list loads,
                // so the permission prompt is never the price of turning one off.
                ForEach(trustedBluetooth) { place in
                    HStack {
                        Label(place.label, systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Button("Remove", role: .destructive) { presence.remove(place) }
                    }
                }
            }
        } header: {
            Text("Trusted Bluetooth devices")
        } footer: {
            Text("Counts only while the device is actually connected. A Bluetooth address is not proof of identity — treat this as convenience, not security.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
