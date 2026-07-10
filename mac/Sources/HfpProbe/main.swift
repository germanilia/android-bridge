import Foundation
import IOBluetooth

// HFP audio spike probe (Increment 2).
//
// Question this answers on YOUR hardware: can this Mac become the Bluetooth Hands-Free (HF)
// endpoint for the paired phone, so that cellular call audio routes into CoreAudio
// (Mac speaker + mic) while Android Bridge keeps controlling calls over Wi-Fi/TLS?
//
// macOS does NOT natively present itself as a phone's headset — that is why apps like
// Phone Amego exist. The only supported path is the IOBluetooth Hands-Free API used below.
// This probe does the minimum to prove the route: it finds the paired phone, confirms it
// advertises the HFP Audio Gateway service, creates an IOBluetoothHandsFreeDevice, and
// connects. On modern macOS (Sequoia+/Apple Silicon) some devs report the connect/SDP path
// silently failing — this probe surfaces exactly where it succeeds or breaks.
//
// Run:  cd mac && swift run HfpProbe
// Prep: pair the phone to this Mac in System Settings ▸ Bluetooth first, and start a call
//       on the phone to observe the audio route (SCO) coming up.

let hfpGatewayUUID = IOBluetoothSDPUUID(uuid16: BluetoothSDPUUID16(kBluetoothSDPUUID16ServiceClassHandsFreeAudioGateway.rawValue))

setbuf(stdout, nil) // unbuffered so nothing is lost if the probe is interrupted mid-run

// Also mirror every line to a log file so the probe is observable when launched as a bundled
// .app via `open` (no attached terminal). Path overridable via HFP_PROBE_LOG.
let logPath = ProcessInfo.processInfo.environment["HFP_PROBE_LOG"]
    ?? (NSHomeDirectory() as NSString).appendingPathComponent("hfp-probe.log")
try? "".write(toFile: logPath, atomically: true, encoding: .utf8) // truncate at start
let logFH = FileHandle(forWritingAtPath: logPath)
func log(_ s: String) {
    print("[hfp-probe] \(s)")
    logFH?.write(Data("[hfp-probe] \(s)\n".utf8))
}
log("log file: \(logPath)")

/// Delegate that narrates the Hands-Free connection + call/audio state so we can see the
/// exact point of failure on this Mac/OS. All methods are optional on the protocol.
final class ProbeDelegate: NSObject, IOBluetoothHandsFreeDeviceDelegate {
    func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        log("service disconnected: status \(status ?? 0)")
    }

    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        log("🔊 SCO audio link OPENED — call audio should now be on the Mac speaker/mic (status \(status ?? 0))")
    }

    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) {
        log("SCO audio link closed: status \(status ?? 0)")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isServiceAvailable value: NSNumber!) {
        // 1 here means the RFCOMM/service link to the phone's gateway is up.
        log("✅ gateway service available = \(value ?? 0) (1 = HF link is up)")
    }

    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive value: NSNumber!) {
        log("call active = \(value ?? 0)")
    }
}

// 1. Enumerate paired devices and pick the phone (HFP Audio Gateway).
guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice], !paired.isEmpty else {
    log("No paired Bluetooth devices. Pair your phone in System Settings ▸ Bluetooth, then retry.")
    exit(1)
}

// Optional CLI arg: a name/address substring to force a specific target, e.g.
//   swift run HfpProbe galaxy
// Use this when the phone is paired but its HFP-AG SDP record is stale/uncached (a known
// Sequoia symptom) — we then attempt the HF connection anyway and let the delegate report.
let targetArg = CommandLine.arguments.dropFirst().first?.lowercased()

func looksLikeGateway(_ d: IOBluetoothDevice) -> Bool { d.getServiceRecord(for: hfpGatewayUUID) != nil }

log("Paired devices:")
for d in paired {
    log("  • \(d.name ?? "?") [\(d.addressString ?? "?")]\(looksLikeGateway(d) ? "  ← HFP Audio Gateway (phone)" : "")")
}

let phone: IOBluetoothDevice?
if let t = targetArg {
    phone = paired.first { ($0.name?.lowercased().contains(t) ?? false) || ($0.addressString?.lowercased().contains(t) ?? false) }
    if phone == nil { log("❌ No paired device matches \"\(t)\". Pair the phone first, or check the name/address above.") }
} else {
    phone = paired.first(where: looksLikeGateway)
    if phone == nil {
        log("❌ No paired device advertises the HFP Audio Gateway service.")
        log("   The phone must be paired over Bluetooth AND expose Hands-Free/telephony to this Mac.")
        log("   If the phone IS paired but not detected (stale SDP), force it by name:")
        log("     swift run HfpProbe <name-substring>   e.g.  swift run HfpProbe galaxy")
    }
}
guard let phone else { exit(2) }

if !looksLikeGateway(phone) {
    log("⚠️  \(phone.name ?? "?") has no cached HFP-AG SDP record — attempting HF connect anyway (the API tries regardless).")
}
log("Target: \(phone.name ?? "?") [\(phone.addressString ?? "?")]")

// 2. Create the Hands-Free device and connect. This is the step that regresses on some
//    Sequoia+/Apple Silicon builds — if `connectionComplete` never fires, that is the finding.
let delegate = ProbeDelegate()
guard let hf = IOBluetoothHandsFreeDevice(device: phone, delegate: delegate) else {
    log("❌ IOBluetoothHandsFreeDevice(device:delegate:) returned nil — HF role unavailable on this Mac/OS.")
    exit(3)
}

log("baseband connected before connect(): \(phone.isConnected())")
log("Connecting as Hands-Free unit… (start/answer a call on the phone to bring up SCO audio)")
hf.connect()

// 3. Poll the real connection state every 2s. Delegate callbacks are unreliable on some
//    Sequoia/Apple-Silicon builds, so we watch hf.isConnected (service link) and
//    phone.isConnected() (baseband ACL) directly and report every change.
log("Listening 90s, polling link state every 2s. Place/answer a call on the phone. Ctrl-C to stop.")
var lastSvc = false
var lastBase = phone.isConnected()
let deadline = Date().addingTimeInterval(90)
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    let svc = hf.isConnected
    let base = phone.isConnected()
    if svc != lastSvc {
        log(svc ? "✅ hf.isConnected = true — Hands-Free service link is UP" : "hf.isConnected = false — service link dropped")
        lastSvc = svc
    }
    if base != lastBase {
        log("baseband connected = \(base)")
        lastBase = base
    }
}
log("Probe window ended. Final: hf.isConnected=\(hf.isConnected), baseband=\(phone.isConnected())")
