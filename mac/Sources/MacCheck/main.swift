import Foundation
import DeviceLinkProtocol
import BridgeCore

// Logic checks for the macOS BridgeCore (mirrors the Android Kotest suite). Dependency-free harness
// because this environment lacks XCTest. Exits non-zero on any failure.

var runner = PropertyRunner(seed: 0xCAFE, iterations: 300)

// MessageRouter
runner.expect("router routes a valid message to its handler") {
    let router = MessageRouter()
    var got: Message?
    router.register(MessageTypes.clipUpdate) { got = $0 }
    let ok = router.route(Message(id: "1", type: MessageTypes.clipUpdate))
    return ok && got != nil
}
runner.expect("router drops an unrouted message (fail-closed)") {
    !MessageRouter().route(Message(id: "1", type: MessageTypes.smsReceived))
}
runner.expect("router drops an invalid (version mismatch) message") {
    let router = MessageRouter()
    router.register(MessageTypes.clipUpdate) { _ in }
    return !router.route(Message(id: "1", type: MessageTypes.clipUpdate, protocolVersion: 2))
}

// PluginRegistry
runner.expect("all features enabled by default") {
    let r = PluginRegistry()
    return FeatureId.allCases.allSatisfy { r.isEnabled($0) }
}
runner.expect("disable then enable a feature") {
    let r = PluginRegistry()
    r.disable(.sms); let a = !r.isEnabled(.sms)
    r.enable(.sms); return a && r.isEnabled(.sms)
}

// Pairing
runner.expect("QR create → consume round-trips and pins the peer") {
    let a = PairingManager(store: InMemorySecureStore())
    let b = PairingManager(store: InMemorySecureStore())
    let idA = a.generateIdentity("galaxy")
    let qr = a.createPairingQr(idA, host: "192.168.1.5", port: 5599)
    guard let peer = try? b.consumePairingQr(qr) else { return false }
    return peer.deviceId == idA.deviceId && peer.deviceName == "galaxy" && b.isPinned(peer.fingerprint) && b.listPaired().count == 1
}
runner.expect("fingerprint is deterministic") {
    let pm = PairingManager(store: InMemorySecureStore())
    let id = pm.generateIdentity("mac")
    return pm.fingerprint(of: id.publicKeyB64) == pm.fingerprint(of: id.publicKeyB64)
}
runner.expect("unpair removes the peer") {
    let a = PairingManager(store: InMemorySecureStore())
    let b = PairingManager(store: InMemorySecureStore())
    let idA = a.generateIdentity("galaxy")
    guard let peer = try? b.consumePairingQr(a.createPairingQr(idA, host: "h", port: 1)) else { return false }
    b.unpair(peer.deviceId)
    return b.listPaired().isEmpty
}
runner.expect("tampered fingerprint is rejected") {
    let a = PairingManager(store: InMemorySecureStore())
    let b = PairingManager(store: InMemorySecureStore())
    let idA = a.generateIdentity("galaxy")
    let qr = a.createPairingQr(idA, host: "h", port: 1).replacingOccurrences(of: a.fingerprint(of: idA.publicKeyB64), with: "00:11:22")
    do { _ = try b.consumePairingQr(qr); return false } catch { return true }
}

// Stream round-trip (PBT-03)
runner.check("PBT-03: chunk then reassemble round-trips") { p in
    let n = p.int(0, 5000)
    var data = Data()
    for _ in 0..<n { data.append(p.byte()) }
    let frames = StreamChunker.chunk(streamId: 42, data: data, chunkSize: 256)
    let reasm = StreamReassembler(streamId: 42)
    for f in frames { if !reasm.accept(f) { return false } }
    return reasm.complete && reasm.result() == data
}
runner.expect("reassembler faults on a sequence gap") {
    let frames = StreamChunker.chunk(streamId: 1, data: Data(repeating: 0, count: 600), chunkSize: 256)
    let reasm = StreamReassembler(streamId: 1)
    _ = reasm.accept(frames[0])
    return !reasm.accept(frames[2])
}

// Clipboard
runner.expect("clipboard default is manual") {
    let policy = ClipboardSyncPolicy()
    return policy.shouldSend(userInitiated: false) == false && policy.shouldSend(userInitiated: true) == true
}

// Mappers produce valid messages
runner.expect("mappers produce valid protocol messages") {
    let msgs = [
        Mappers.notification(pkg: "com.x", title: "t", text: "b", postedAt: 1),
        Mappers.smsReceived(threadId: 1, address: "+1", body: "hi", receivedAt: 2),
        Mappers.incomingCall(number: "+1", contactName: "Al"),
        Mappers.callAction("answer"),
        Mappers.clipboard("copied"),
    ]
    return msgs.allSatisfy { validate($0) == nil }
}

// Self-signed identity generation (swift-certificates) — a real, passing check.
if let id = try? SelfSignedIdentity.generate(commonName: "spike-mac") {
    runner.expect("generates a self-signed cert (DER \(id.certificateDER.count)B, fp \(id.fingerprint.prefix(11))…)", !id.certificateDER.isEmpty)
    // NOTE (informational, not a gating check): bridging to a SecIdentity for Network.framework mutual
    // TLS is unresolved for an unsigned/ad-hoc binary (keychain entitlement / param errors). Tracked as
    // the remaining Mac-transport work; see aidlc-docs.
    if let _ = try? id.makeSecIdentity(label: "AndroidBridge-Spike") {
        print("ℹ️  SecIdentity bridge: OK")
    } else {
        print("ℹ️  SecIdentity bridge: NOT yet available in this (unsigned) context — remaining Mac-transport work")
    }
} else {
    runner.expect("generates a self-signed cert", false)
}

print("\n— \(runner.passed) checks passed, \(runner.failures.count) failed —")
if !runner.allPassed {
    for f in runner.failures { print(f) }
    exit(1)
}
print("ALL MAC CORE CHECKS PASSED")
