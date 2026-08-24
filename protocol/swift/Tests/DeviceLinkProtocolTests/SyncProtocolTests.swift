import XCTest
import SwiftCheck
import Foundation
@testable import DeviceLinkProtocol

private struct GeneratedSyncOperation: Arbitrary {
    let value: SyncOperation

    static var arbitrary: Gen<GeneratedSyncOperation> {
        Gen.zip(
            String.arbitrary.suchThat { !$0.isEmpty },
            String.arbitrary.suchThat { !$0.isEmpty },
            UInt16.arbitrary,
            Gen<SyncOperationKind>.fromElements(of: SyncOperationKind.allCases)
        ).map { operationId, actorId, sequence, kind in
            GeneratedSyncOperation(value: SyncOperation(
                operationId: operationId,
                actorId: actorId,
                sequence: Int64(sequence) + 1,
                kind: kind,
                target: "notes/a.md",
                messageType: kind == .message ? MessageTypes.notifPosted : nil,
                resultDigest: kind == .tombstone ? nil : String(repeating: "a", count: 64),
                blobDigest: kind == .tombstone ? nil : String(repeating: "a", count: 64),
                byteCount: kind == .tombstone ? 0 : 12,
                mediaType: kind == .tombstone ? nil : "application/octet-stream"
            ))
        }
    }
}

final class SyncProtocolTests: XCTestCase {
    func testSyncModelsRoundTrip() throws {
        let cursor = SyncCursor(actorId: "phone", throughSequence: 41)
        let capabilities = CapabilityAnnouncement(actorId: "phone", capabilities: SyncCapability.allCases)
        let resume = ResumeRequest(cursor: cursor)
        let acknowledgement = SyncAcknowledgement(cursor: cursor, operationId: "op-41")
        let operation = SyncOperation(operationId: "op-42", actorId: "phone", sequence: 42, kind: .snapshot, target: "notes/a.md", baseDigest: "b", resultDigest: "r", blobDigest: "r", byteCount: 3, mediaType: "text/markdown")
        let chunk = TransferChunk(operationId: "op-42", index: 0, offset: 0, dataBase64: Data([1, 2, 3]).base64EncodedString(), digest: "digest", isFinal: true)

        XCTAssertEqual(try SyncModelCodec.decode(CapabilityAnnouncement.self, from: SyncModelCodec.encode(capabilities)), capabilities)
        XCTAssertEqual(try SyncModelCodec.decode(ResumeRequest.self, from: SyncModelCodec.encode(resume)), resume)
        XCTAssertEqual(try SyncModelCodec.decode(SyncAcknowledgement.self, from: SyncModelCodec.encode(acknowledgement)), acknowledgement)
        XCTAssertEqual(try SyncModelCodec.decode(SyncOperation.self, from: SyncModelCodec.encode(operation)), operation)
        XCTAssertEqual(try SyncModelCodec.decode(TransferChunk.self, from: SyncModelCodec.encode(chunk)), chunk)
    }

    func testSyncOperationRoundTripProperty() {
        property("PBT: immutable sync operations round-trip") <- forAll { (generated: GeneratedSyncOperation) in
            let operation = generated.value
            return (try? SyncModelCodec.decode(SyncOperation.self, from: SyncModelCodec.encode(operation))) == operation
        }
    }

    func testCursorMonotonicityProperty() {
        property("PBT: cursor advancement is monotonic") <- forAll { (current: UInt16, increment: UInt16) in
            let cursor = SyncCursor(actorId: "mac", throughSequence: Int64(current))
            return (try? cursor.advanced(to: Int64(current) + Int64(increment)))?.throughSequence == Int64(current) + Int64(increment)
        }
        XCTAssertThrowsError(try SyncCursor(actorId: "mac", throughSequence: 2).advanced(to: 1))
    }

    func testReplayClassificationIsExplicit() throws {
        XCTAssertEqual(try ReplayClassifier.classify(MessageTypes.smsReceived), .durable)
        XCTAssertEqual(try ReplayClassifier.classify(MessageTypes.clipUpdate), .coalesced)
        XCTAssertEqual(try ReplayClassifier.classify(MessageTypes.callAction), .liveOnly)
        XCTAssertEqual(try ReplayClassifier.classify(MessageTypes.screenFrame), .liveOnly)
        XCTAssertNoThrow(try MessageTypes.known.forEach { _ = try ReplayClassifier.classify($0) })
        XCTAssertTrue(MessageTypes.sync.isSubset(of: MessageTypes.known))
    }

    func testTruncatedBinaryFrameProperty() {
        property("PBT: truncated binary frames fail closed") <- forAll { (rawLength: UInt16) in
            let declared = Int(rawLength) % ProtocolConstants.maxFramePayloadBytes + 1
            var bytes = [UInt8](repeating: 0, count: ProtocolConstants.frameHeaderBytes)
            writeU32BE(&bytes, 8, UInt32(declared))
            do {
                _ = try FrameCodec.decodeFrame(bytes)
                return false
            } catch {
                return error as? ProtocolError == .badFrameHeader
            }
        }
    }

    func testOversizedBinaryFrameProperty() {
        property("PBT: oversized binary frames fail before payload extraction") <- forAll { (extra: UInt16) in
            var bytes = [UInt8](repeating: 0, count: ProtocolConstants.frameHeaderBytes)
            writeU32BE(&bytes, 8, UInt32(ProtocolConstants.maxFramePayloadBytes + Int(extra) + 1))
            do {
                _ = try FrameCodec.decodeFrame(bytes)
                return false
            } catch {
                return error as? ProtocolError == .oversize
            }
        }
    }

    func testStreamDecoderRejectsOversizedHeader() {
        let decoder = ControlStreamDecoder()
        var header = [UInt8](repeating: 0, count: 4)
        writeU32BE(&header, 0, UInt32(ProtocolConstants.maxControlBytes + 1))
        XCTAssertThrowsError(try decoder.ingest(header)) {
            XCTAssertEqual($0 as? ProtocolError, .oversize)
        }
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testStreamDecoderFragmentationProperty() {
        property("PBT: stream decoder accepts arbitrary receive fragmentation") <- forAll { (rawSize: UInt8) in
            let fragmentSize = max(1, Int(rawSize % 32))
            let message = Message(id: "fragmented", type: MessageTypes.syncCapabilities)
            guard let encoded = try? MessageCodec.encode(message) else { return false }
            let decoder = ControlStreamDecoder()
            var decoded: [Message] = []
            var offset = 0
            while offset < encoded.count {
                let end = min(offset + fragmentSize, encoded.count)
                guard let batch = try? decoder.ingest(Array(encoded[offset..<end])) else { return false }
                decoded.append(contentsOf: batch)
                offset = end
            }
            return decoded == [message] && decoder.bufferedByteCount == 0
        }
    }
}
