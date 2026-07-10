import XCTest
import SwiftCheck
import Foundation
@testable import DeviceLinkProtocol

// ---- Domain generators (PBT-07) ----

private let lowerChar = Gen<Character>.fromElements(in: Character("a")...Character("z"))

private func lowerString(_ range: ClosedRange<Int>) -> Gen<String> {
    Gen<Int>.choose((range.lowerBound, range.upperBound)).flatMap { n in
        lowerChar.proliferate(withSize: n).map { String($0) }
    }
}

private let jsonValueGen: Gen<JSONValue> = Gen<JSONValue>.one(of: [
    lowerString(0...12).map { JSONValue.string($0) },
    Gen<Int>.choose((-100_000, 100_000)).map { JSONValue.int($0) },
    Bool.arbitrary.map { JSONValue.bool($0) },
])

private let payloadGen: Gen<[String: JSONValue]> =
    Gen<Int>.choose((0, 6)).flatMap { n in
        Gen.zip(lowerString(1...8), jsonValueGen).proliferate(withSize: n).map { pairs in
            Dictionary(pairs, uniquingKeysWith: { a, _ in a })
        }
    }

private let replyToGen: Gen<String?> = Gen<String?>.one(of: [
    Gen.pure(String?.none),
    lowerString(1...20).map { Optional($0) },
])

private let messageGen: Gen<Message> = Gen.zip(
    lowerString(1...20),
    Gen<String>.fromElements(of: Array(MessageTypes.known)),
    replyToGen,
    payloadGen
).map { id, type, replyTo, payload in
    Message(id: id, type: type, replyTo: replyTo, payload: payload)
}

// Arbitrary conformances so SwiftCheck's `forAll` (and its shrinking machinery) can drive them.
extension Message: Arbitrary {
    public static var arbitrary: Gen<Message> { messageGen }
}

struct FrameCase { let streamId: UInt32; let sequence: UInt32; let flags: Int; let payload: Data }
extension FrameCase: Arbitrary {
    static var arbitrary: Gen<FrameCase> {
        Gen.zip(
            UInt32.arbitrary,
            UInt32.arbitrary,
            Gen<Int>.choose((0, 255)),
            UInt8.arbitrary.proliferate(withSize: 64).map { Data($0) }
        ).map { FrameCase(streamId: $0.0, sequence: $0.1, flags: $0.2, payload: $0.3) }
    }
}

final class ProtocolPropertyTests: XCTestCase {

    func testRoundTripControlMessage() {
        property("PBT-02: decode(encode(m)) == m") <- forAll { (m: Message) in
            (try? MessageCodec.decode(MessageCodec.encode(m))) == m
        }
    }

    func testSelfDelimitingFraming() {
        property("PBT-03: control framing is self-delimiting") <- forAll { (msgs: [Message]) in
            var bytes: [UInt8] = []
            for m in msgs { bytes.append(contentsOf: (try? MessageCodec.encode(m)) ?? []) }
            return ((try? MessageCodec.decodeStream(bytes)) ?? []) == msgs
        }
    }

    func testFrameRoundTrip() {
        property("PBT-03: decodeFrame(encodeFrame(h,p)) == (h,p)") <- forAll { (c: FrameCase) in
            let header = FrameHeader(streamId: c.streamId, sequence: c.sequence, length: c.payload.count, flags: c.flags)
            return (try? FrameCodec.decodeFrame(FrameCodec.encodeFrame(header, c.payload))) == Frame(header: header, payload: c.payload)
        }
    }
}

final class ProtocolExampleTests: XCTestCase {

    private func framed(_ json: String) -> [UInt8] {
        let body = [UInt8](json.utf8)
        var f = [UInt8](repeating: 0, count: 4 + body.count)
        writeU32BE(&f, 0, UInt32(body.count))
        for i in 0..<body.count { f[4 + i] = body[i] }
        return f
    }

    func testEncodesLengthPrefix() throws {
        let m = Message(id: "abc", type: MessageTypes.linkHeartbeat)
        let bytes = try MessageCodec.encode(m)
        XCTAssertEqual(Int(readU32BE(bytes, 0)), bytes.count - 4)
        XCTAssertEqual(try MessageCodec.decode(bytes), m)
    }

    func testRejectsUnknownType() {
        XCTAssertThrowsError(try MessageCodec.decode(framed("{\"id\":\"x\",\"type\":\"bogus.type\"}"))) {
            XCTAssertEqual($0 as? ProtocolError, .unknownType)
        }
    }

    func testRejectsOversize() {
        var oversize = [UInt8](repeating: 0, count: 8)
        writeU32BE(&oversize, 0, UInt32(ProtocolConstants.maxControlBytes + 1))
        XCTAssertThrowsError(try MessageCodec.decode(oversize)) {
            XCTAssertEqual($0 as? ProtocolError, .oversize)
        }
    }

    func testRejectsVersionMismatch() {
        XCTAssertThrowsError(try MessageCodec.decode(framed("{\"id\":\"x\",\"type\":\"link.hello\",\"protocolVersion\":2}"))) {
            XCTAssertEqual($0 as? ProtocolError, .versionMismatch)
        }
    }

    func testCrossLanguageVectors() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vectors/control-messages.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            let m = try MessageCodec.decode(framed(line))
            XCTAssertTrue(MessageTypes.known.contains(m.type))
        }
    }
}
