import AppKit
import DeviceLinkProtocol
import Foundation
import XCTest
@testable import BridgeCore

final class SecondBrainSyncTests: XCTestCase {
    func testScanCreatesImmutableSnapshotsAndTombstonesWithoutEchoes() throws {
        let root = temporaryRoot()
        let support = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: support)
        }
        let meetingPhotos = root.appendingPathComponent("meetings/android-bridge/photos/meeting-1", isDirectory: true)
        try FileManager.default.createDirectory(at: meetingPhotos, withIntermediateDirectories: true)
        try Data("# First".utf8).write(to: root.appendingPathComponent("note.md"))
        try pngData().write(to: meetingPhotos.appendingPathComponent("photo.png"))
        try jpegData().write(to: meetingPhotos.appendingPathComponent("photo.jpg"))
        try pngData().write(to: root.appendingPathComponent("unrelated-photo.png"))
        try Data("audio".utf8).write(to: meetingPhotos.appendingPathComponent("secret-name.m4a"))
        try Data("not an image".utf8).write(to: meetingPhotos.appendingPathComponent("invalid.jpg"))

        let session = RelayReplaySession(
            journal: try DurableSyncJournal(rootURL: support.appendingPathComponent("journal"), actorId: "mac"),
            actorId: "mac",
            peerActorId: "phone"
        )
        let manifest = try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("manifest"))
        let sync = SecondBrainDeltaSynchronizer(store: SecondBrainStore(rootURL: root), manifest: manifest, replaySession: session)

        _ = try sync.scan()
        var operations = try session.journal.pending()
        let pngPath = "meetings/android-bridge/photos/meeting-1/photo.png"
        let jpegPath = "meetings/android-bridge/photos/meeting-1/photo.jpg"
        XCTAssertEqual(Set(operations.map(\.target)), ["note.md", pngPath, jpegPath])
        XCTAssertTrue(operations.allSatisfy { $0.kind == .snapshot })
        XCTAssertFalse(operations.map(\.target).contains { $0.contains("secret-name.m4a") || $0.hasPrefix("/") })
        XCTAssertTrue(try sync.scan().isEmpty)
        let restarted = SecondBrainDeltaSynchronizer(
            store: SecondBrainStore(rootURL: root),
            manifest: try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("manifest")),
            replaySession: session
        )
        XCTAssertTrue(try restarted.scan().isEmpty)

        let firstDigest = try XCTUnwrap(operations.first { $0.target == "note.md" }?.resultDigest)
        try Data("# Changed".utf8).write(to: root.appendingPathComponent("note.md"), options: .atomic)
        try FileManager.default.removeItem(at: meetingPhotos.appendingPathComponent("photo.png"))
        _ = try restarted.scan()

        operations = try session.journal.pending()
        let changed = try XCTUnwrap(operations.last { $0.target == "note.md" })
        XCTAssertEqual(changed.kind, .snapshot)
        XCTAssertEqual(changed.baseDigest, firstDigest)
        let deleted = try XCTUnwrap(operations.last { $0.target == pngPath })
        XCTAssertEqual(deleted.kind, .tombstone)
        XCTAssertEqual(deleted.baseDigest, ContentHash.sha256(pngData()))
        XCTAssertNil(deleted.blobDigest)
        XCTAssertTrue(try restarted.scan().isEmpty)
    }

    func testIncomingCompareAndSetPreservesVisibleConflictAndDoesNotEcho() throws {
        let root = temporaryRoot()
        let support = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: support)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)
        let local = Data("# Local edit".utf8)
        let incoming = Data("# Phone edit".utf8)
        try local.write(to: root.appendingPathComponent("notes/plan.md"), options: .atomic)

        let session = RelayReplaySession(
            journal: try DurableSyncJournal(rootURL: support.appendingPathComponent("journal"), actorId: "mac"),
            actorId: "mac",
            peerActorId: "phone"
        )
        let manifest = try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("manifest"))
        let sync = SecondBrainDeltaSynchronizer(store: SecondBrainStore(rootURL: root), manifest: manifest, replaySession: session)
        let operation = SyncOperation(
            operationId: "phone-1",
            actorId: "phone",
            sequence: 1,
            kind: .snapshot,
            target: "notes/plan.md",
            baseDigest: ContentHash.sha256(Data("# Shared base".utf8)),
            resultDigest: ContentHash.sha256(incoming),
            blobDigest: ContentHash.sha256(incoming),
            byteCount: Int64(incoming.count),
            mediaType: "text/markdown"
        )

        let result = try sync.apply(operation, content: incoming)

        XCTAssertEqual(result.outcome, .conflictPreserved)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("notes/plan.md")), local)
        let conflictPath = try XCTUnwrap(result.conflictPath)
        XCTAssertTrue(conflictPath.contains(".conflict-phone-0000000001.md"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(conflictPath)), incoming)
        XCTAssertTrue(try sync.scan().isEmpty)
        XCTAssertEqual(try manifest.entries()["notes/plan.md"], ContentHash.sha256(local))
        XCTAssertEqual(try manifest.entries()[conflictPath], ContentHash.sha256(incoming))
    }

    func testConflictingTombstoneKeepsLocalFileAndWritesVisibleMarker() throws {
        let root = temporaryRoot()
        let support = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: support)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let local = Data("# New local edit".utf8)
        try local.write(to: root.appendingPathComponent("note.md"))
        let session = RelayReplaySession(
            journal: try DurableSyncJournal(rootURL: support.appendingPathComponent("journal"), actorId: "mac"),
            actorId: "mac",
            peerActorId: "phone"
        )
        let sync = SecondBrainDeltaSynchronizer(
            store: SecondBrainStore(rootURL: root),
            manifest: try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("manifest")),
            replaySession: session
        )
        let tombstone = operation(
            sequence: 3,
            kind: .tombstone,
            target: "note.md",
            base: ContentHash.sha256(Data("# Old base".utf8)),
            content: nil
        )

        let result = try sync.apply(tombstone, content: nil)

        XCTAssertEqual(result.outcome, .conflictPreserved)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("note.md")), local)
        let conflictPath = try XCTUnwrap(result.conflictPath)
        XCTAssertTrue(conflictPath.hasSuffix(".deleted.md"))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent(conflictPath), encoding: .utf8).contains("Deletion conflict"))
        XCTAssertTrue(try sync.scan().isEmpty)
    }

    func testIncomingRejectsAbsoluteAndTraversalTargets() throws {
        let root = temporaryRoot()
        let support = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: support)
        }
        let session = RelayReplaySession(
            journal: try DurableSyncJournal(rootURL: support.appendingPathComponent("journal"), actorId: "mac"),
            actorId: "mac",
            peerActorId: "phone"
        )
        let sync = SecondBrainDeltaSynchronizer(
            store: SecondBrainStore(rootURL: root),
            manifest: try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("manifest")),
            replaySession: session
        )
        let content = Data("# Outside".utf8)

        XCTAssertThrowsError(try sync.apply(operation(sequence: 1, kind: .snapshot, target: "/tmp/outside.md", base: nil, content: content), content: content))
        XCTAssertThrowsError(try sync.apply(operation(sequence: 2, kind: .snapshot, target: "notes/../../outside.md", base: nil, content: content), content: content))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/outside.md"))
    }

    func testIncomingMatchingBaseAppliesAndTombstoneDeletes() throws {
        let root = temporaryRoot()
        let support = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: support)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let base = Data("# Base".utf8)
        let incoming = Data("# Incoming".utf8)
        try base.write(to: root.appendingPathComponent("note.md"))
        let session = RelayReplaySession(
            journal: try DurableSyncJournal(rootURL: support.appendingPathComponent("journal"), actorId: "mac"),
            actorId: "mac",
            peerActorId: "phone"
        )
        let sync = SecondBrainDeltaSynchronizer(
            store: SecondBrainStore(rootURL: root),
            manifest: try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("manifest")),
            replaySession: session
        )
        let snapshot = operation(sequence: 1, kind: .snapshot, target: "note.md", base: ContentHash.sha256(base), content: incoming)
        XCTAssertEqual(try sync.apply(snapshot, content: incoming).outcome, .applied)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("note.md")), incoming)

        let tombstone = operation(sequence: 2, kind: .tombstone, target: "note.md", base: ContentHash.sha256(incoming), content: nil)
        XCTAssertEqual(try sync.apply(tombstone, content: nil).outcome, .deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("note.md").path))
        XCTAssertTrue(try sync.scan().isEmpty)
    }

    private func operation(sequence: Int64, kind: SyncOperationKind, target: String, base: String?, content: Data?) -> SyncOperation {
        let digest = content.map(ContentHash.sha256)
        return SyncOperation(
            operationId: "phone-\(sequence)",
            actorId: "phone",
            sequence: sequence,
            kind: kind,
            target: target,
            baseDigest: base,
            resultDigest: digest,
            blobDigest: digest,
            byteCount: Int64(content?.count ?? 0),
            mediaType: content == nil ? nil : "text/markdown"
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("brain-sync-\(UUID().uuidString)")
    }

    private func pngData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }

    private func jpegData() throws -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        let representation = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(representation.representation(using: .jpeg, properties: [:]))
    }
}
