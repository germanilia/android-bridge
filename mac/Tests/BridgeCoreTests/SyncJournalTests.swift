import XCTest
import SwiftCheck
import Foundation
@testable import BridgeCore
import DeviceLinkProtocol

final class SyncJournalTests: XCTestCase {
    func testAtomicPersistenceAndOwnedBlob() throws {
        try withJournalRoot { root in
            let bytes = Data("hello journal".utf8)
            let journal = try DurableSyncJournal(rootURL: root, actorId: "mac")
            let operation = try journal.enqueue(operationId: "op-1", kind: .snapshot, target: "notes/a.md", content: bytes, mediaType: "text/markdown")

            XCTAssertEqual(operation.sequence, 1)
            XCTAssertEqual(operation.blobDigest, ContentHash.sha256(bytes))
            XCTAssertEqual(try DurableSyncJournal(rootURL: root, actorId: "mac").pending(), [operation])
            XCTAssertEqual(try DurableSyncJournal(rootURL: root, actorId: "mac").readBlob(digest: try XCTUnwrap(operation.blobDigest)), bytes)
        }
    }

    func testAcknowledgementAndResumeRules() throws {
        try withJournalRoot { root in
            let journal = try DurableSyncJournal(rootURL: root, actorId: "mac")
            let operations = try (1...5).map { index in
                try journal.enqueue(operationId: "op-\(index)", kind: .message, target: "event-\(index)", content: Data([UInt8(index)]), messageType: MessageTypes.notifPosted)
            }

            try journal.acknowledge(through: 2)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("blobs/\(try XCTUnwrap(operations[0].blobDigest))").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("blobs/\(try XCTUnwrap(operations[2].blobDigest))").path))
            XCTAssertEqual(try journal.pending().map(\.sequence), [3, 4, 5])
            XCTAssertEqual(try journal.pending(after: 3).map(\.sequence), [4, 5])
            XCTAssertThrowsError(try journal.acknowledge(through: 1)) { XCTAssertEqual($0 as? SyncJournalError, .cursorRegression) }
            XCTAssertThrowsError(try journal.acknowledge(through: 6)) { XCTAssertEqual($0 as? SyncJournalError, .cursorBeyondHighWater) }
            XCTAssertThrowsError(try journal.pending(after: 1)) { XCTAssertEqual($0 as? SyncJournalError, .staleCursor) }
        }
    }

    func testDeduplicationAndSequenceGap() throws {
        try withJournalRoot { root in
            let journal = try DurableSyncJournal(rootURL: root, actorId: "mac")
            let first = remoteOperation(id: "remote-1", sequence: 1)
            XCTAssertEqual(try journal.incomingDisposition(first), .apply)
            XCTAssertTrue(try journal.recordApplied(first))
            XCTAssertEqual(try journal.incomingDisposition(first), .duplicate)
            XCTAssertFalse(try journal.recordApplied(first))
            XCTAssertEqual(try journal.incomingDisposition(remoteOperation(id: "remote-3", sequence: 3)), .gap)
            XCTAssertEqual(try DurableSyncJournal(rootURL: root, actorId: "mac").receivedThrough(actorId: "phone"), 1)
        }
    }

    func testHashConflictOutcomes() {
        let base = Data("base".utf8)
        let incoming = Data("incoming".utf8)
        XCTAssertEqual(NoteConflictResolver.resolve(current: base, incoming: incoming, baseDigest: ContentHash.sha256(base)).outcome, .applied)
        XCTAssertEqual(NoteConflictResolver.resolve(current: incoming, incoming: incoming, baseDigest: ContentHash.sha256(base)).outcome, .unchanged)
        XCTAssertEqual(NoteConflictResolver.resolve(current: base, incoming: nil, baseDigest: ContentHash.sha256(base)).outcome, .deleted)
        let conflict = NoteConflictResolver.resolve(current: Data("local".utf8), incoming: incoming, baseDigest: ContentHash.sha256(base))
        XCTAssertEqual(conflict.outcome, .conflictPreserved)
        XCTAssertEqual(conflict.canonical, Data("local".utf8))
        XCTAssertEqual(conflict.conflict, incoming)
    }

    func testTransferChunkBoundsOrderingAndDigest() throws {
        let data = Data((0..<1000).map { UInt8($0 % 251) })
        let chunks = try SyncTransferChunker.chunk(operationId: "op", data: data, chunkSize: 128)
        XCTAssertTrue(try chunks.allSatisfy { try $0.decodedData().count <= 128 })
        let reassembler = SyncTransferReassembler(operationId: "op", expectedDigest: ContentHash.sha256(data))
        for chunk in chunks { try reassembler.accept(chunk) }
        XCTAssertEqual(try reassembler.result(), data)

        let corrupted = TransferChunk(operationId: chunks[0].operationId, index: chunks[0].index, offset: chunks[0].offset, dataBase64: Data([9]).base64EncodedString(), digest: chunks[0].digest, isFinal: chunks[0].isFinal)
        XCTAssertThrowsError(try SyncTransferReassembler(operationId: "op", expectedDigest: ContentHash.sha256(data)).accept(corrupted)) {
            XCTAssertEqual($0 as? SyncJournalError, .digestMismatch)
        }
    }

    func testRestartResumeProperty() {
        property("PBT: restart resumes exact unacknowledged suffix") <- forAll { (generated: [UInt8], selector: UInt8) in
            let payloads = generated.prefix(20).enumerated().map { Data([$0.element]) }
            guard !payloads.isEmpty else { return true }
            let root = self.temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                let journal = try DurableSyncJournal(rootURL: root, actorId: "mac")
                for (index, payload) in payloads.enumerated() {
                    _ = try journal.enqueue(operationId: "op-\(index + 1)", kind: .message, target: "event-\(index + 1)", content: payload, messageType: MessageTypes.smsReceived)
                }
                let acknowledged = Int64(Int(selector) % (payloads.count + 1))
                try journal.acknowledge(through: acknowledged)
                let expected = acknowledged == Int64(payloads.count) ? [] : Array((acknowledged + 1)...Int64(payloads.count))
                return try DurableSyncJournal(rootURL: root, actorId: "mac").pending().map(\.sequence) == expected
            } catch {
                return false
            }
        }
    }

    func testDuplicateDeliveryProperty() {
        property("PBT: duplicate delivery is idempotent") <- forAll { (rawCount: UInt8) in
            let count = Int(rawCount % 40) + 1
            let root = self.temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                let journal = try DurableSyncJournal(rootURL: root, actorId: "mac")
                for sequence in 1...count {
                    let operation = self.remoteOperation(id: "remote-\(sequence)", sequence: Int64(sequence))
                    guard try journal.recordApplied(operation), try !journal.recordApplied(operation) else { return false }
                }
                return try journal.receivedThrough(actorId: "phone") == Int64(count)
            } catch {
                return false
            }
        }
    }

    func testConflictPreservationProperty() {
        property("PBT: conflicts preserve both distinct byte sequences") <- forAll { (localBytes: [UInt8], incomingBytes: [UInt8]) in
            let local = Data(localBytes.prefix(64))
            var incoming = Data(incomingBytes.prefix(64))
            if incoming == local { incoming.append(1) }
            var nonBase = local
            nonBase.append(0)
            let resolution = NoteConflictResolver.resolve(current: local, incoming: incoming, baseDigest: ContentHash.sha256(nonBase))
            return resolution.outcome == .conflictPreserved && resolution.canonical == local && resolution.conflict == incoming
        }
    }

    func testChunkReassemblyProperty() {
        property("PBT: chunk reassembly preserves arbitrary bytes") <- forAll { (bytes: [UInt8], rawSize: UInt16) in
            let data = Data(bytes.prefix(5000))
            let chunkSize = Int(rawSize % 512) + 1
            do {
                let chunks = try SyncTransferChunker.chunk(operationId: "op", data: data, chunkSize: chunkSize)
                let reassembler = SyncTransferReassembler(operationId: "op", expectedDigest: ContentHash.sha256(data))
                for chunk in chunks { try reassembler.accept(chunk) }
                return try reassembler.result() == data
            } catch {
                return false
            }
        }
    }

    private func withJournalRoot(_ body: (URL) throws -> Void) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("android-bridge-\(UUID().uuidString)")
    }

    private func remoteOperation(id: String, sequence: Int64) -> SyncOperation {
        SyncOperation(operationId: id, actorId: "phone", sequence: sequence, kind: .message, target: "event-\(sequence)", messageType: MessageTypes.notifPosted, resultDigest: String(repeating: "a", count: 64), blobDigest: String(repeating: "a", count: 64), byteCount: 1)
    }
}
