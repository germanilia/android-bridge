import Foundation
import DeviceLinkProtocol

// Property + example checks for the Device-Link Protocol (PBT-02/-03 + fail-closed examples).
// Dependency-free; deterministic via seed. Exits non-zero on any failure.

let knownTypes = Array(MessageTypes.known)

func genLowerString(_ p: inout PRNG, _ lo: Int, _ hi: Int) -> String {
    let n = p.int(lo, hi)
    var s = ""
    for _ in 0..<n { s.append(Character(UnicodeScalar(UInt8(97 + p.int(0, 25))))) }
    return s
}

func genJSONValue(_ p: inout PRNG) -> JSONValue {
    switch p.int(0, 2) {
    case 0: return .string(genLowerString(&p, 0, 12))
    case 1: return .int(p.int(-100_000, 100_000))
    default: return .bool(p.bool())
    }
}

func genPayload(_ p: inout PRNG) -> [String: JSONValue] {
    let n = p.int(0, 6)
    var d: [String: JSONValue] = [:]
    for _ in 0..<n { d[genLowerString(&p, 1, 8)] = genJSONValue(&p) }
    return d
}

func genMessage(_ p: inout PRNG) -> Message {
    let id = genLowerString(&p, 1, 20)
    let type = knownTypes[p.int(0, knownTypes.count - 1)]
    let replyTo: String? = p.bool() ? genLowerString(&p, 1, 20) : nil
    return Message(id: id, type: type, replyTo: replyTo, payload: genPayload(&p))
}

var runner = PropertyRunner(seed: 0xC0FFEE, iterations: 500)

// PBT-02: round-trip control message
runner.check("PBT-02: decode(encode(m)) == m") { p in
    let m = genMessage(&p)
    guard let bytes = try? MessageCodec.encode(m), let back = try? MessageCodec.decode(bytes) else { return false }
    return back == m
}

// PBT-03: self-delimiting control framing
runner.check("PBT-03: control framing is self-delimiting") { p in
    let count = p.int(0, 5)
    var msgs: [Message] = []
    var bytes: [UInt8] = []
    for _ in 0..<count {
        let m = genMessage(&p)
        msgs.append(m)
        guard let e = try? MessageCodec.encode(m) else { return false }
        bytes.append(contentsOf: e)
    }
    guard let decoded = try? MessageCodec.decodeStream(bytes) else { return false }
    return decoded == msgs
}

// PBT-03: frame round-trip
runner.check("PBT-03: decodeFrame(encodeFrame(h,p)) == (h,p)") { p in
    let len = p.int(0, 2048)
    var payload = Data()
    for _ in 0..<len { payload.append(p.byte()) }
    let h = FrameHeader(streamId: p.u32(), sequence: p.u32(), length: len, flags: p.int(0, 255))
    guard let enc = try? FrameCodec.encodeFrame(h, payload), let dec = try? FrameCodec.decodeFrame(enc) else { return false }
    return dec == Frame(header: h, payload: payload)
}

// Example: length prefix
do {
    let m = Message(id: "abc", type: MessageTypes.linkHeartbeat)
    let bytes = (try? MessageCodec.encode(m)) ?? []
    runner.expect("encodes a 4-byte length prefix", !bytes.isEmpty && Int(readU32BE(bytes, 0)) == bytes.count - 4)
}

// Example: reject unknown type
func framed(_ json: String) -> [UInt8] {
    let body = [UInt8](json.utf8)
    var f = [UInt8](repeating: 0, count: 4 + body.count)
    writeU32BE(&f, 0, UInt32(body.count))
    for i in 0..<body.count { f[4 + i] = body[i] }
    return f
}
do {
    var threw = false
    do { _ = try MessageCodec.decode(framed("{\"id\":\"x\",\"type\":\"bogus.type\"}")) }
    catch { threw = (error as? ProtocolError) == .unknownType }
    runner.expect("rejects unknown message type", threw)
}
do {
    var ok = false
    var oversize = [UInt8](repeating: 0, count: 8)
    writeU32BE(&oversize, 0, UInt32(ProtocolConstants.maxControlBytes + 1))
    do { _ = try MessageCodec.decode(oversize) } catch { ok = (error as? ProtocolError) == .oversize }
    runner.expect("rejects oversize control message (anti-DoS)", ok)
}
do {
    var ok = false
    do { _ = try MessageCodec.decode(framed("{\"id\":\"x\",\"type\":\"link.hello\",\"protocolVersion\":2}")) }
    catch { ok = (error as? ProtocolError) == .versionMismatch }
    runner.expect("rejects version mismatch", ok)
}
do {
    let h = FrameHeader(streamId: 7, sequence: 3, length: 0, flags: ProtocolConstants.flagEndOfStream)
    let dec = try? FrameCodec.decodeFrame(FrameCodec.encodeFrame(h, Data()))
    runner.expect("marks END_OF_STREAM frames", dec?.header.isEndOfStream == true)
}

// Cross-language interop: decode the shared canonical wire vectors (also decoded by the Kotlin suite).
do {
    let vectorsURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ProtocolCheck
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // swift
        .deletingLastPathComponent() // protocol
        .appendingPathComponent("vectors/control-messages.jsonl")
    if let text = try? String(contentsOf: vectorsURL, encoding: .utf8) {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        var allOk = !lines.isEmpty
        for line in lines {
            let body = [UInt8](line.utf8)
            var f = [UInt8](repeating: 0, count: 4 + body.count)
            writeU32BE(&f, 0, UInt32(body.count))
            for i in 0..<body.count { f[4 + i] = body[i] }
            if let m = try? MessageCodec.decode(f) {
                if !MessageTypes.known.contains(m.type) || m.id.isEmpty { allOk = false }
            } else {
                allOk = false
            }
        }
        runner.expect("cross-language: decodes \(lines.count) shared wire vectors", allOk)
    } else {
        runner.expect("cross-language: vectors file present", false)
    }
}

print("\n— \(runner.passed) checks passed, \(runner.failures.count) failed —")
if !runner.allPassed {
    for f in runner.failures { print(f) }
    exit(1)
}
print("ALL PROTOCOL CHECKS PASSED")
