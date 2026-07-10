import XCTest
import SwiftCheck
import Foundation
@testable import BridgeCore
import DeviceLinkProtocol

final class MessageRouterTests: XCTestCase {
    func testRoutesValidMessage() {
        let router = MessageRouter()
        var got: Message?
        router.register(MessageTypes.clipUpdate) { got = $0 }
        XCTAssertTrue(router.route(Message(id: "1", type: MessageTypes.clipUpdate)))
        XCTAssertNotNil(got)
    }
    func testDropsUnrouted() {
        XCTAssertFalse(MessageRouter().route(Message(id: "1", type: MessageTypes.smsReceived)))
    }
    func testDropsInvalid() {
        let router = MessageRouter()
        router.register(MessageTypes.clipUpdate) { _ in }
        XCTAssertFalse(router.route(Message(id: "1", type: MessageTypes.clipUpdate, protocolVersion: 2)))
    }
}

final class PluginRegistryTests: XCTestCase {
    func testDefaultsEnabled() {
        let r = PluginRegistry()
        XCTAssertTrue(FeatureId.allCases.allSatisfy { r.isEnabled($0) })
    }
    func testToggle() {
        let r = PluginRegistry()
        r.disable(.sms); XCTAssertFalse(r.isEnabled(.sms))
        r.enable(.sms); XCTAssertTrue(r.isEnabled(.sms))
    }
}

final class PairingTests: XCTestCase {
    func testQrRoundTripAndPin() throws {
        let a = PairingManager(store: InMemorySecureStore())
        let b = PairingManager(store: InMemorySecureStore())
        let idA = a.generateIdentity("galaxy")
        let peer = try b.consumePairingQr(a.createPairingQr(idA, host: "192.168.1.5", port: 5599))
        XCTAssertEqual(peer.deviceId, idA.deviceId)
        XCTAssertTrue(b.isPinned(peer.fingerprint))
        XCTAssertEqual(b.listPaired().count, 1)
    }
    func testTamperRejected() {
        let a = PairingManager(store: InMemorySecureStore())
        let b = PairingManager(store: InMemorySecureStore())
        let idA = a.generateIdentity("galaxy")
        let qr = a.createPairingQr(idA, host: "h", port: 1)
            .replacingOccurrences(of: a.fingerprint(of: idA.publicKeyB64), with: "00:11:22")
        XCTAssertThrowsError(try b.consumePairingQr(qr))
    }
}

final class FeatureTests: XCTestCase {
    func testClipboardDefaultManual() {
        let p = ClipboardSyncPolicy()
        XCTAssertFalse(p.shouldSend(userInitiated: false))
        XCTAssertTrue(p.shouldSend(userInitiated: true))
    }
    func testMappersValid() {
        let msgs = [
            Mappers.notification(pkg: "com.x", title: "t", text: "b", postedAt: 1),
            Mappers.smsReceived(threadId: 1, address: "+1", body: "hi", receivedAt: 2),
            Mappers.incomingCall(number: "+1", contactName: "Al"),
            Mappers.callAction("answer"),
            Mappers.clipboard("copied"),
            Message(id: "m", type: MessageTypes.meetingStart, payload: ["meetingId": .string("m1"), "startedAt": .int(1)]),
        ]
        XCTAssertTrue(msgs.allSatisfy { validate($0) == nil })
    }
    /// call.action "dial" must round-trip through the codec with the number intact,
    /// so the phone can place the call the Mac requested.
    func testCallDialRoundTripsWithNumber() throws {
        let m = Mappers.callAction("dial", number: "+15550100")
        let decoded = try MessageCodec.decode(try MessageCodec.encode(m))
        XCTAssertEqual(decoded.type, MessageTypes.callAction)
        XCTAssertEqual(decoded.payload["action"], .string("dial"))
        XCTAssertEqual(decoded.payload["number"], .string("+15550100"))
        XCTAssertNil(validate(decoded))
    }
}

// Property test (PBT-03): stream chunk/reassemble round-trip.
struct Blob: Arbitrary {
    let data: Data
    static var arbitrary: Gen<Blob> {
        Gen<Int>.choose((0, 3000)).flatMap { n in
            UInt8.arbitrary.proliferate(withSize: n).map { Blob(data: Data($0)) }
        }
    }
}

final class MeetingCaptureTests: XCTestCase {
    func testNotesPlacesPhotoBeforeNearestLaterSegment() {
        let segments = [TranscriptSegment(speaker: "Speaker 1", startMs: 1000, endMs: 2000, text: "hello")]
        let photos = [MeetingPhoto(photoId: "p1", capturedAtMs: 500, fileName: "photo-p1.jpg")]
        let md = NotesBuilder().build(meetingId: "m1", segments: segments, photos: photos)
        XCTAssertTrue(md.contains("![Photo at 500ms](media/photo-p1.jpg)"))
        XCTAssertTrue(md.contains("**Speaker 1** [1000ms]: hello"))
    }
}

final class SummaryRepairTests: XCTestCase {
    func testUnwrapsOllamaTerminalWrappedSummary() {
        // Real artifact shape: `ollama run` wrapped piped output at ~75 cols and
        // reprinted the cut word on the next line (ANSI erase codes already stripped).
        let corrupted = """
        # Incremental Meeting Summary

        ## Context
        The meeting appears to be an advanced technical review and development plan
        planning session focused on migrating complex AI functionality from older s
        systems/APIs to a new, stabilized production environment. Key concerns revo
        revolve around API reliability, response formatting consistency across mult
        multiple Large Language Models (LLMs), performance tuning, and ensuring dat
        data integrity during the transition.

        ## Topics Discussed
        *   **Response Formatting Layer:** The discussion heavily focused on the di
        difficulty of maintaining consistent output formatting from AI responses. A
        """
        let repaired = SummaryRepair.unwrap(corrupted)
        XCTAssertTrue(repaired.contains("development planning session"))
        XCTAssertFalse(repaired.contains("plan\nplanning"))
        XCTAssertTrue(repaired.contains("from older systems/APIs"))
        XCTAssertTrue(repaired.contains("concerns revolve around"))
        XCTAssertTrue(repaired.contains("across multiple Large Language Models"))
        XCTAssertTrue(repaired.contains("ensuring data integrity"))
        XCTAssertTrue(repaired.contains("focused on the difficulty of maintaining"))
        // Structure survives: headings stay on their own lines, bullets keep markers.
        XCTAssertTrue(repaired.contains("\n## Context\n"))
        XCTAssertTrue(repaired.contains("\n*   **Response Formatting Layer:**"))
    }

    func testUnwrapDropsFullWordReprintedAtWrap() {
        let corrupted = """
        comprehensive educational management system designed for students, covering
        covering both general education pathways and specialized programs. The disc
        discussion involves multiple stakeholder perspectives, including those relat
        related to individual schools and regional authorities.
        """
        let repaired = SummaryRepair.unwrap(corrupted)
        XCTAssertTrue(repaired.contains("students, covering both"))
        XCTAssertFalse(repaired.contains("covering covering"))
        XCTAssertTrue(repaired.contains("The discussion involves"))
        XCTAssertTrue(repaired.contains("those related to individual schools"))
    }

    func testCleanSummaryPassesThroughUntouched() {
        let clean = """
        # Meeting Summary

        A normal paragraph that was generated by the HTTP API and has no artificial wrapping at all, no matter how long the line gets.

        - First action item
        - Second action item
        """
        XCTAssertEqual(SummaryRepair.unwrap(clean), clean)
    }
}

final class StreamPropertyTests: XCTestCase {
    func testChunkReassembleRoundTrip() {
        property("PBT-03: chunk then reassemble round-trips") <- forAll { (blob: Blob) in
            let frames = StreamChunker.chunk(streamId: 42, data: blob.data, chunkSize: 256)
            let reasm = StreamReassembler(streamId: 42)
            for f in frames { if !reasm.accept(f) { return false } }
            return reasm.complete && reasm.result() == blob.data
        }
    }
}
