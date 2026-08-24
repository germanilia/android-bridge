import XCTest
import Foundation
@testable import BridgeCore

final class MeetingContentMirrorTests: XCTestCase {
    func testSyncWritesTextWithoutAudioDetailsAndUpdatesInPlace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("private-meeting")
        defer { try? FileManager.default.removeItem(at: root) }
        let mirror = MeetingContentMirror(root: root)
        let audio = source.appendingPathComponent("media/chunk-secret-name.m4a")
        let image = source.appendingPathComponent("media/photo-private-name.png")
        try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData().write(to: image)
        let first = meeting(source: source, audio: audio, image: image, summary: "First summary")

        try mirror.sync([first])
        let note = try XCTUnwrap(generatedNotes(in: root).first)
        var body = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(body.contains("# Client planning"))
        XCTAssertTrue(body.contains("First summary"))
        XCTAssertTrue(body.contains("Transcript text"))
        XCTAssertFalse(body.contains("Recordings:"))
        XCTAssertFalse(body.contains("chunk-secret-name.m4a"))
        XCTAssertFalse(body.contains(source.path))
        XCTAssertFalse(body.contains("/Users/"))
        XCTAssertTrue(body.contains("![Meeting photo 1](photos/2026-08-24-client-planning/photo-001.png)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("meetings/android-bridge/photos/2026-08-24-client-planning/photo-001.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("meetings/android-bridge/chunk-secret-name.m4a").path))

        try mirror.sync([meeting(source: source, audio: audio, image: image, summary: "Updated summary")])
        body = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(body.contains("Updated summary"))
        XCTAssertFalse(body.contains("First summary"))
    }

    func testSyncRemovesOnlyStaleGeneratedMeetingNotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mirror = MeetingContentMirror(root: root)
        try mirror.sync([meeting(source: root.appendingPathComponent("source"), audio: nil, image: nil, summary: "Summary")])
        let owned = root.appendingPathComponent("keep-me.md")
        try "Personal".write(to: owned, atomically: true, encoding: .utf8)

        try mirror.sync([])

        XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(generatedNotes(in: root).isEmpty)
    }

    private func generatedNotes(in root: URL) -> [URL] {
        let directory = root.appendingPathComponent("meetings/android-bridge", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "index.md" }
    }

    private func pngData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }

    private func meeting(source: URL, audio: URL?, image: URL?, summary: String) -> MeetingRecord {
        MeetingRecord(
            id: "2026-08-24-client-planning",
            title: "Client planning",
            company: "Example Co",
            brainPath: nil,
            url: source,
            notesURL: source.appendingPathComponent("notes.md"),
            date: Date(timeIntervalSince1970: 1_777_000_000),
            audioFiles: audio.map { [$0] } ?? [],
            imageFiles: image.map { [$0] } ?? [],
            audioCount: audio == nil ? 0 : 1,
            photoCount: image == nil ? 0 : 1,
            transcript: "Me [0ms]: Transcript text chunk-secret-name.m4a at \(source.path) and file:///Users/person/private.m4a",
            summary: summary,
            questions: "Q: Decision? A: Ship it.",
            notesUpdatedAt: Date(timeIntervalSince1970: 1_777_000_100),
            isActive: false,
            endDate: Date(timeIntervalSince1970: 1_777_000_900),
            processingState: .ready,
            calendarEvent: nil
        )
    }
}
