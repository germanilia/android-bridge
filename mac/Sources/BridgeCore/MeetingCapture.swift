import Foundation
import DeviceLinkProtocol

public struct TranscriptSegment: Codable, Equatable {
    public let speaker: String
    public let startMs: Int
    public let endMs: Int
    public let text: String
}

public struct MeetingPhoto: Codable, Equatable {
    public let photoId: String
    public let capturedAtMs: Int
    public let fileName: String
}

public struct MeetingRecord: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let url: URL
    public let notesURL: URL?
    public let date: Date
    public let audioFiles: [URL]
    public let imageFiles: [URL]
    public let audioCount: Int
    public let photoCount: Int
    public let transcript: String
    public let summary: String
    public let questions: String
    public let notesUpdatedAt: Date?
    public let isActive: Bool
}

public final class MeetingStore {
    public var rootURL: URL { root }
    public static let shared = MeetingStore()
    private let fm = FileManager.default
    private let root: URL

    public init(root: URL? = nil) {
        let configured = UserDefaults.standard.string(forKey: "meetings.root")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let root {
            self.root = root
        } else if configured?.isEmpty == false {
            self.root = URL(fileURLWithPath: configured!)
        } else {
            let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
            self.root = base.appendingPathComponent("AndroidBridgeMeetings", isDirectory: true)
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    public func meetingDir(_ meetingId: String) -> URL {
        let dir = root.appendingPathComponent(safe(meetingId), isDirectory: true)
        try? fm.createDirectory(at: dir.appendingPathComponent("media", isDirectory: true), withIntermediateDirectories: true)
        return dir
    }

    public func markStarted(meetingId: String, startedAtMs: Int) {
        let url = meetingDir(meetingId).appendingPathComponent("startedAt.txt")
        try? String(startedAtMs).write(to: url, atomically: true, encoding: .utf8)
    }

    public func saveAudio(meetingId: String, sequence: Int, data: Data) -> URL {
        let file = meetingDir(meetingId).appendingPathComponent("media", isDirectory: true).appendingPathComponent(String(format: "chunk-%04d.m4a", sequence))
        try? data.write(to: file)
        return file
    }

    public func savePhoto(meetingId: String, photoId: String, data: Data) -> URL {
        let destination = meetingDir(meetingId).appendingPathComponent("media", isDirectory: true).appendingPathComponent("photo-\(safe(photoId)).jpg")
        try? data.write(to: destination)
        return destination
    }

    public func appendTranscript(meetingId: String, segment: TranscriptSegment) {
        let url = meetingDir(meetingId).appendingPathComponent("transcript.jsonl")
        if let data = try? JSONEncoder().encode(segment), let line = String(data: data, encoding: .utf8)?.appending("\n") {
            if let fh = try? FileHandle(forWritingTo: url) { fh.seekToEndOfFile(); fh.write(Data(line.utf8)); try? fh.close() }
            else { try? Data(line.utf8).write(to: url) }
        }
    }

    public func writeNotes(meetingId: String, photos: [MeetingPhoto] = []) -> URL {
        let dir = meetingDir(meetingId)
        let title = titleOverride(in: dir) ?? (UUID(uuidString: meetingId) == nil ? meetingId : "Live Meeting")
        return writeNotes(in: dir, meetingId: title, photos: photos, generateSummary: true)
    }

    public func writeNotesIncremental(meetingId: String, newSegments: [TranscriptSegment], photos: [MeetingPhoto] = []) -> URL {
        let dir = meetingDir(meetingId)
        let title = titleOverride(in: dir) ?? (UUID(uuidString: meetingId) == nil ? meetingId : "Live Meeting")
        return writeNotesIncremental(in: dir, meetingId: title, newSegments: newSegments, photos: photos)
    }

    public func finalizeMeeting(meetingId: String, photos: [MeetingPhoto] = []) -> URL {
        let dir = meetingDir(meetingId)
        let segments = readSegments(in: dir)
        let title = titleOverride(in: dir) ?? LLMService(feature: .summarize).title(segments.map(\.text).joined(separator: "\n")) ?? "Meeting"
        let stamp = DateFormatter.meetingFolder.string(from: Date())
        let destination = root.appendingPathComponent("\(stamp) - \(safe(title))", isDirectory: true)
        if destination != dir, !fm.fileExists(atPath: destination.path) {
            try? fm.moveItem(at: dir, to: destination)
            return writeNotes(in: destination, meetingId: title, photos: photos, generateSummary: true)
        }
        return writeNotes(in: dir, meetingId: title, photos: photos, generateSummary: true)
    }

    private func writeNotes(in dir: URL, meetingId: String, photos: [MeetingPhoto], generateSummary: Bool) -> URL {
        let segments = readSegments(in: dir)
        let transcriptText = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted(by: { $0.startMs < $1.startMs }).map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        let summary = currentSummary(in: dir) ?? (generateSummary && !transcriptText.isEmpty ? LLMService(feature: .summarize).summarize(transcriptText) : nil)
        return writeNotesFile(in: dir, meetingId: meetingId, segments: segments, photos: photos, summary: summary)
    }

    private func writeNotesIncremental(in dir: URL, meetingId: String, newSegments: [TranscriptSegment], photos: [MeetingPhoto]) -> URL {
        let segments = readSegments(in: dir)
        let delta = newSegments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        let previous = currentSummary(in: dir)
        let summary = delta.isEmpty ? previous : LLMService(feature: .summarize).updateSummary(previous: previous, newTranscript: delta)
        return writeNotesFile(in: dir, meetingId: meetingId, segments: segments, photos: photos, summary: summary)
    }

    private func writeNotesFile(in dir: URL, meetingId: String, segments: [TranscriptSegment], photos: [MeetingPhoto], summary: String?) -> URL {
        if let summary { try? summary.write(to: summaryURL(in: dir), atomically: true, encoding: .utf8) }
        let markdown = NotesBuilder().build(meetingId: meetingId, segments: segments, photos: photos, summary: summary)
        let fileName = "\(safe(meetingId)).md"
        let url = dir.appendingPathComponent(fileName == ".md" ? "notes.md" : fileName)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        if url.lastPathComponent != "notes.md" { try? markdown.write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8) }
        return url
    }

    public func listMeetings(activeIds: Set<String> = []) -> [MeetingRecord] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return dirs.filter { $0.hasDirectoryPath }.compactMap { record(for: $0, activeIds: activeIds) }
            .sorted { $0.date > $1.date }
    }

    public func deleteMeeting(_ meeting: MeetingRecord) {
        try? fm.removeItem(at: meeting.url)
    }

    public func trashMeeting(_ meeting: MeetingRecord) {
        try? fm.trashItem(at: meeting.url, resultingItemURL: nil)
    }

    public func hasReadableMeeting(at url: URL) -> Bool {
        record(for: url, activeIds: []) != nil
    }

    public func renameMeeting(_ meeting: MeetingRecord, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        try? clean.write(to: meeting.url.appendingPathComponent("title.txt"), atomically: true, encoding: .utf8)
        let dir: URL
        if UUID(uuidString: meeting.url.lastPathComponent) == nil {
            let prefix = DateFormatter.meetingFolder.string(from: meeting.date)
            let destination = root.appendingPathComponent("\(prefix) - \(safe(clean))", isDirectory: true)
            if destination != meeting.url, !fm.fileExists(atPath: destination.path) { try? fm.moveItem(at: meeting.url, to: destination) }
            dir = fm.fileExists(atPath: destination.path) ? destination : meeting.url
        } else {
            dir = meeting.url
        }
        _ = writeNotes(in: dir, meetingId: clean, photos: [], generateSummary: false)
    }

    /// Re-runs Whisper over every placeholder segment (chunks recorded while
    /// transcription was failing, e.g. ffmpeg missing from PATH) and rebuilds
    /// the summary and notes from the recovered text.
    public func retranscribeMeeting(_ meeting: MeetingRecord) {
        let whisper = WhisperTranscriptionService()
        let media = meeting.url.appendingPathComponent("media", isDirectory: true)
        let marker = "[Audio chunk saved for local transcription: "
        let segments = readSegments(in: meeting.url).map { segment -> TranscriptSegment in
            guard segment.text.hasPrefix(marker), segment.text.hasSuffix("]") else { return segment }
            let name = String(segment.text.dropFirst(marker.count).dropLast())
            let file = media.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { return segment }
            return whisper.transcribe(file: file, startMs: segment.startMs, endMs: segment.endMs, speaker: segment.speaker)
        }
        let transcriptURL = meeting.url.appendingPathComponent("transcript.jsonl")
        let body = segments.compactMap { segment -> String? in
            guard let data = try? JSONEncoder().encode(segment) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
        try? (body + "\n").write(to: transcriptURL, atomically: true, encoding: .utf8)
        // Drop cached summaries and summarize from scratch: writeNotes' usual
        // notes.md fallback would resurrect the stale placeholder-era summary.
        if let files = try? fm.contentsOfDirectory(at: meeting.url, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("summary") && file.pathExtension == "md" {
                try? fm.removeItem(at: file)
            }
        }
        let transcriptText = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.text.hasPrefix(marker) }
            .sorted(by: { $0.startMs < $1.startMs }).map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        let summary = transcriptText.isEmpty ? nil : LLMService(feature: .summarize).summarize(transcriptText)
        _ = writeNotesFile(in: meeting.url, meetingId: meeting.title, segments: segments, photos: [], summary: summary)
    }

    public func regenerateSummary(_ meeting: MeetingRecord) {
        let segments = readSegments(in: meeting.url)
        let transcriptText = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted(by: { $0.startMs < $1.startMs }).map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        let summary = currentSummary(in: meeting.url, allowNotesFallback: false) ?? (transcriptText.isEmpty ? nil : LLMService(feature: .summarize).summarize(transcriptText))
        _ = writeNotesFile(in: meeting.url, meetingId: meeting.title, segments: segments, photos: [], summary: summary)
    }

    public func renameSpeaker(_ meeting: MeetingRecord, from oldName: String, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !clean.isEmpty else { return }
        let segments = readSegments(in: meeting.url).map { segment in
            TranscriptSegment(speaker: segment.speaker == oldName ? clean : segment.speaker, startMs: segment.startMs, endMs: segment.endMs, text: segment.text)
        }
        let transcriptURL = meeting.url.appendingPathComponent("transcript.jsonl")
        let body = segments.compactMap { segment -> String? in
            guard let data = try? JSONEncoder().encode(segment) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
        try? (body + "\n").write(to: transcriptURL, atomically: true, encoding: .utf8)
        _ = writeNotes(in: meeting.url, meetingId: meeting.title, photos: [], generateSummary: false)
    }

    public func answerQuestion(_ meeting: MeetingRecord, question: String) -> String? {
        let transcript = readSegments(in: meeting.url).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        guard let answer = LLMService(feature: .chat).answer(question: question, transcript: transcript) else { return nil }
        let url = meeting.url.appendingPathComponent("questions.md")
        let entry = "## Q: \(question)\n\n\(answer)\n\n"
        if let data = entry.data(using: .utf8), let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); try? fh.close()
        } else { try? entry.write(to: url, atomically: true, encoding: .utf8) }
        return answer
    }

    public func mergeMeetings(_ records: [MeetingRecord]) -> URL? {
        guard records.count >= 2 else { return nil }
        let title = records.map(\.title).joined(separator: " + ")
        let id = "\(DateFormatter.meetingFolder.string(from: Date())) - \(safe(title))"
        let dir = root.appendingPathComponent(id, isDirectory: true)
        let media = dir.appendingPathComponent("media", isDirectory: true)
        try? fm.createDirectory(at: media, withIntermediateDirectories: true)
        var transcript = ""
        for record in records {
            let sourceMedia = record.url.appendingPathComponent("media", isDirectory: true)
            let files = (try? fm.contentsOfDirectory(at: sourceMedia, includingPropertiesForKeys: nil)) ?? []
            for file in files { try? fm.copyItem(at: file, to: media.appendingPathComponent("\(safe(record.title))-\(file.lastPathComponent)")) }
            transcript += (try? String(contentsOf: record.url.appendingPathComponent("transcript.jsonl"), encoding: .utf8)) ?? ""
        }
        try? transcript.write(to: dir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)
        _ = writeNotes(in: dir, meetingId: title, photos: [], generateSummary: true)
        return dir
    }

    private func record(for dir: URL, activeIds: Set<String>) -> MeetingRecord? {
        let media = dir.appendingPathComponent("media", isDirectory: true)
        let mediaFiles = (try? fm.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)) ?? []
        let notes = dir.appendingPathComponent("notes.md")
        let notesText = (try? String(contentsOf: notes, encoding: .utf8)) ?? ""
        let segments = readSegments(in: dir)
        let transcript = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { "\($0.speaker) [\($0.startMs)ms]: \($0.text)" }.joined(separator: "\n")
        let summary = SummaryRepair.unwrap(notesText.components(separatedBy: "## Transcript").first?.components(separatedBy: "## Summary").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let audioFiles = mediaFiles.filter { ["m4a", "3gp", "wav"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let imageFiles = mediaFiles.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let date = startedDate(in: dir) ?? parsedDate(from: dir.lastPathComponent) ?? ((try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        let notesUpdatedAt = (try? notes.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        return MeetingRecord(
            id: dir.lastPathComponent,
            title: titleOverride(in: dir) ?? displayTitle(dir.lastPathComponent),
            url: dir,
            notesURL: fm.fileExists(atPath: notes.path) ? notes : nil,
            date: date,
            audioFiles: audioFiles,
            imageFiles: imageFiles,
            audioCount: audioFiles.count,
            photoCount: imageFiles.count,
            transcript: transcript,
            summary: summary,
            questions: (try? String(contentsOf: dir.appendingPathComponent("questions.md"), encoding: .utf8)) ?? "",
            notesUpdatedAt: notesUpdatedAt,
            isActive: activeIds.contains(dir.lastPathComponent)
        )
    }

    private func readSegments(in dir: URL) -> [TranscriptSegment] {
        let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
        let lines = (try? String(contentsOf: transcriptURL, encoding: .utf8).split(separator: "\n").map(String.init)) ?? []
        return lines.compactMap { try? JSONDecoder().decode(TranscriptSegment.self, from: Data($0.utf8)) }
    }

    private func currentSummary(in dir: URL, allowNotesFallback: Bool = true) -> String? {
        if let cached = try? String(contentsOf: summaryURL(in: dir), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !cached.isEmpty { return SummaryRepair.unwrap(cached) }
        guard allowNotesFallback else { return nil }
        let notes = dir.appendingPathComponent("notes.md")
        let text = (try? String(contentsOf: notes, encoding: .utf8)) ?? ""
        let summary = text.components(separatedBy: "## Transcript").first?.components(separatedBy: "## Summary").last?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary, !summary.isEmpty, !summary.contains("Live transcript is updating") else { return nil }
        return SummaryRepair.unwrap(summary)
    }

    private func summaryURL(in dir: URL) -> URL {
        let language = UserDefaults.standard.string(forKey: "summaryLanguage") ?? "Original"
        let type = UserDefaults.standard.string(forKey: "summaryType") ?? "Detailed"
        return dir.appendingPathComponent("summary-\(safe(language))-\(safe(type)).md")
    }

    private func titleOverride(in dir: URL) -> String? {
        let raw = try? String(contentsOf: dir.appendingPathComponent("title.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }

    private func startedDate(in dir: URL) -> Date? {
        let url = dir.appendingPathComponent("startedAt.txt")
        guard let raw = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), let ms = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private func parsedDate(from name: String) -> Date? {
        guard name.count >= 16 else { return nil }
        return DateFormatter.meetingFolder.date(from: String(name.prefix(16)))
    }

    private func displayTitle(_ name: String) -> String {
        if UUID(uuidString: name) != nil { return "Live Meeting" }
        guard name.count > 19, parsedDate(from: name) != nil else { return name }
        return String(name.dropFirst(19)).replacingOccurrences(of: "-", with: " ")
    }

    private func safe(_ s: String) -> String {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapped = String(cleaned.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " ") ? $0 : "-" })
        return mapped.replacingOccurrences(of: "  ", with: " ").replacingOccurrences(of: " ", with: "-")
    }
}

/// Repairs summaries produced by the old `ollama run` CLI pipeline, which word-wrapped
/// piped output at terminal width (~75 cols): a word cut at the margin was erased with
/// ANSI codes and reprinted on the next line. Stripping the ANSI codes left hard line
/// breaks plus the duplicated fragment ("…a comprehens\ncomprehensive…"). This unwraps
/// those paragraphs and drops the duplicate fragments. Clean text passes through untouched.
public enum SummaryRepair {
    public static func unwrap(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard overlapPairCount(lines) >= 2 else { return text }
        var out: [String] = []
        var current: String?
        func flush() {
            if let line = current { out.append(line) }
            current = nil
        }
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                out.append("")
            } else if line.hasPrefix("#") || line.hasPrefix("|") {
                // Headings and table rows are single-line; never absorb continuations.
                flush()
                out.append(line)
            } else if startsBlock(line) {
                flush()
                current = line
            } else if let acc = current {
                current = join(acc, line)
            } else {
                current = line
            }
        }
        flush()
        return out.joined(separator: "\n")
    }

    // Runs only on documents already detected as wrap-corrupted, so a trailing word
    // that prefixes the next line's first word is treated as the cut fragment even
    // when it is a single character ("…older s" / "systems/APIs…").
    private static func join(_ acc: String, _ next: String) -> String {
        if let last = acc.split(separator: " ").last.map(String.init),
           let first = next.split(separator: " ").first.map(String.init),
           first.hasPrefix(last) {
            let trimmedAcc = String(acc.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
            return trimmedAcc.isEmpty ? next : "\(trimmedAcc) \(next)"
        }
        return "\(acc) \(next)"
    }

    private static func overlapPairCount(_ lines: [String]) -> Int {
        var count = 0
        for (line, next) in zip(lines, lines.dropFirst()) {
            guard line.count >= 55,
                  let last = line.split(separator: " ").last.map(String.init),
                  let first = next.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init),
                  last.count >= 2, first.hasPrefix(last)
            else { continue }
            count += 1
        }
        return count
    }

    private static func startsBlock(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") || line.hasPrefix("|") || line.hasPrefix(">") { return true }
        if let dot = line.firstIndex(of: "."), dot != line.startIndex, line[..<dot].allSatisfy({ $0.isNumber }) { return true }
        return false
    }
}

public struct NotesBuilder {
    public init() {}
    public func build(meetingId: String, segments: [TranscriptSegment], photos: [MeetingPhoto], summary: String? = nil) -> String {
        let summary = summary ?? "Live transcript is updating. Final summary is created when the meeting stops."
        var out = "# Meeting \(meetingId)\n\n## Summary\n\n\(summary)\n\n## Transcript\n\n"
        let sortedPhotos = photos.sorted { $0.capturedAtMs < $1.capturedAtMs }
        var used = Set<String>()
        for s in segments.filter({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).sorted(by: { $0.startMs < $1.startMs }) {
            for p in sortedPhotos where !used.contains(p.photoId) && p.capturedAtMs <= s.startMs {
                out += "![Photo at \(p.capturedAtMs)ms](media/\(p.fileName))\n\n"
                used.insert(p.photoId)
            }
            out += "**\(s.speaker)** [\(s.startMs)ms]: \(s.text)\n\n"
        }
        for p in sortedPhotos where !used.contains(p.photoId) {
            out += "![Photo at \(p.capturedAtMs)ms](media/\(p.fileName))\n\n"
        }
        return out
    }
}

public enum LLMFeature: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case chat = "Chat"
    case secondBrainSearch = "Second Brain Search"
    case secondBrainQA = "Second Brain Q&A"
    case secondBrainCRUD = "Second Brain CRUD"

    public var id: String { rawValue }
    public var key: String { rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: "And") }
}

public struct LLMConfig {
    public let usePi: Bool
    public let model: String

    public static func config(for feature: LLMFeature) -> LLMConfig {
        let defaults = UserDefaults.standard
        let key = feature.key
        return LLMConfig(
            usePi: defaults.bool(forKey: "llm.\(key).usePi"),
            model: defaults.string(forKey: "llm.\(key).model") ?? "gemma4:e4b"
        )
    }
}

public struct LLMService {
    public let feature: LLMFeature
    public init(feature: LLMFeature) { self.feature = feature }

    public func summarize(_ transcript: String) -> String? {
        let language = UserDefaults.standard.string(forKey: "summaryLanguage") ?? "Original"
        let summaryType = UserDefaults.standard.string(forKey: "summaryType") ?? "Detailed"
        let languageInstruction = language == "Original"
            ? "Write the summary in the original language of the transcript. If the transcript is mixed-language, use the dominant language."
            : "Write the summary in \(language)."
        let typeInstruction = summaryType == "Short"
            ? "Write a compact executive summary: decisions, blockers, and action items only."
            : "Write a clear concise meeting summary, not a transcript rewrite. Focus on confirmed technical/business content. Ignore garbled speech, incidental navigation, UI clicking, repeated phrases, and uncertain fragments unless they affect an action item. Use these sections only: 1) Summary, 2) Decisions, 3) Action Items, 4) Open Questions/Risks. Keep bullets short and concrete. Do not invent context. If something is unclear, put it under Open Questions/Risks instead of expanding it."
        return run("Summarize the meeting transcript so far. \(languageInstruction) \(typeInstruction) Return clean Markdown only. No code fences. No thinking.\n\nTranscript:\n\(transcript)", feature: feature)
    }

    public func updateSummary(previous: String?, newTranscript: String) -> String? {
        let language = UserDefaults.standard.string(forKey: "summaryLanguage") ?? "Original"
        let summaryType = UserDefaults.standard.string(forKey: "summaryType") ?? "Detailed"
        let languageInstruction = language == "Original"
            ? "Keep the summary in the original/dominant transcript language."
            : "Write the summary in \(language)."
        let typeInstruction = summaryType == "Short"
            ? "Keep it short: decisions, blockers, and action items only."
            : "Keep the summary clear and concise. Preserve confirmed decisions and action items, add only important new information, and remove noise/repetition. Ignore garbled speech, incidental navigation, UI clicking, and uncertain fragments unless they affect an action item. Use sections: Summary, Decisions, Action Items, Open Questions/Risks."
        return run("Update this meeting summary incrementally. \(languageInstruction) \(typeInstruction) Return the complete updated summary as clean Markdown only. No thinking or code fences.\n\nExisting summary:\n\(previous ?? "")\n\nNew transcript chunk:\n\(newTranscript)", feature: feature)
    }

    public func title(_ transcript: String) -> String? {
        run("Create a short meaningful meeting title, 3 to 7 words. Return only the title. Do not include thinking or punctuation.\n\nTranscript:\n\(transcript)", feature: feature)
    }

    public func answer(question: String, transcript: String) -> String? {
        run("Answer the question using only this meeting transcript. If the transcript does not contain the answer, say so briefly. Return only the answer.\n\nQuestion: \(question)\n\nTranscript:\n\(transcript)", feature: feature)
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    // The `ollama run` CLI word-wraps piped output at terminal width, corrupting the
    // text (cut words reprinted on the next line). The HTTP API returns clean text.
    public func run(_ prompt: String, feature override: LLMFeature? = nil) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !CommandLine.arguments.contains(where: { $0.contains("xctest") }) else { return nil }
        let config = LLMConfig.config(for: override ?? feature)
        return config.usePi ? runPi(trimmed, model: config.model) : runOllama(trimmed, model: config.model)
    }

    private func runOllama(_ prompt: String, model: String) -> String? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/generate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 900
        request.httpBody = try? JSONEncoder().encode(GenerateRequest(model: model, prompt: prompt, stream: false))
        let semaphore = DispatchSemaphore(value: 0)
        var output: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) { output = decoded.response }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return output.flatMap(clean)
    }

    private func runPi(_ prompt: String, model: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.environment = environmentWithHomebrewPath()
        let pi = UserDefaults.standard.string(forKey: "pi.executable")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let skill = UserDefaults.standard.string(forKey: "pi.secondBrainSkill")?.trimmingCharacters(in: .whitespacesAndNewlines)
        process.arguments = [pi?.isEmpty == false ? pi! : "pi", "--print", "--no-session", "--no-skills", "--skill", skill?.isEmpty == false ? skill! : NSHomeDirectory() + "/.agents/skills/second-brain", "--model", model, prompt]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return clean(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    private func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        if let range = text.range(of: "...done thinking.", options: .caseInsensitive) { text = String(text[range.upperBound...]) }
        text = text.replacingOccurrences(of: "Thinking...", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```markdown", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// GUI apps launched from Finder get a minimal PATH (/usr/bin:/bin:…), so child
/// processes can't find Homebrew tools like ffmpeg — which mlx_whisper also
/// spawns internally. Prepend the Homebrew locations explicitly.
func environmentWithHomebrewPath() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
    return env
}

public final class WhisperTranscriptionService {
    public init() {}
    public func transcribe(file: URL, startMs: Int, endMs: Int, speaker: String = "Speaker 1") -> TranscriptSegment {
        let text = runWhisper(file) ?? "[Audio chunk saved for local transcription: \(file.lastPathComponent)]"
        return TranscriptSegment(speaker: speaker, startMs: startMs, endMs: endMs, text: text)
    }

    private func runWhisper(_ file: URL) -> String? {
        let resourceTool = Bundle.main.resourceURL?.appendingPathComponent("Tools/mlx_whisper/bin/mlx_whisper")
        let sourceTool = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tools/mlx_whisper/bin/mlx_whisper")
        let local = [resourceTool, sourceTool].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let local else { return nil }
        let audioFile = convertToWavIfNeeded(file) ?? file
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("android-bridge-whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputName = audioFile.deletingPathExtension().lastPathComponent
        let outputFile = outputDir.appendingPathComponent("\(outputName).txt")
        try? FileManager.default.removeItem(at: outputFile)
        let p = Process()
        p.executableURL = local
        p.environment = environmentWithHomebrewPath()
        p.arguments = ["--model", "mlx-community/whisper-large-v3-turbo", "--output-dir", outputDir.path, "--output-name", outputName, "--output-format", "txt", "--verbose", "False", audioFile.path]
        try? p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        guard let raw = try? String(contentsOf: outputFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return cleanTranscript(raw)
    }

    private func cleanTranscript(_ raw: String) -> String? {
        let words = raw.split { $0.isWhitespace || $0.isPunctuation }.map { String($0).lowercased() }
        if words.count >= 5 && Set(words).count <= 2 { return "" }

        var dedupedLines: [String] = []
        var previousLine = ""
        var lineRepeatCount = 0
        for line in raw.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !line.isEmpty {
            let normalized = normalizeForRepeat(line)
            lineRepeatCount = normalized == previousLine ? lineRepeatCount + 1 : 1
            previousLine = normalized
            if lineRepeatCount <= 1 { dedupedLines.append(line) }
        }

        var out: [String] = []
        var previous = ""
        var repeatCount = 0
        for word in dedupedLines.joined(separator: " ").split(separator: " ").map(String.init) {
            let normalized = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            repeatCount = normalized == previous ? repeatCount + 1 : 1
            previous = normalized
            if repeatCount <= 2 { out.append(word) }
        }
        let text = trimRepeatedTail(out).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func normalizeForRepeat(_ text: String) -> String {
        text.lowercased().filter { !$0.isPunctuation && !$0.isWhitespace }
    }

    private func trimRepeatedTail(_ words: [String]) -> [String] {
        guard words.count >= 12 else { return words }
        for size in 2...6 {
            var repeats = 1
            var index = words.count - size
            let phrase = words[index..<words.count].map { normalizeForRepeat($0) }
            while index >= size && words[index - size..<index].map({ normalizeForRepeat($0) }) == phrase {
                repeats += 1
                index -= size
            }
            if repeats >= 3 { return Array(words[..<(index + size)]) }
        }
        return words
    }

    private func convertToWavIfNeeded(_ file: URL) -> URL? {
        guard file.pathExtension.lowercased() != "wav" else { return file }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(file.deletingPathExtension().lastPathComponent).wav")
        try? FileManager.default.removeItem(at: output)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.environment = environmentWithHomebrewPath()
        p.arguments = ["ffmpeg", "-y", "-i", file.path, "-ar", "16000", "-ac", "1", output.path]
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? output : nil
    }
}

private extension DateFormatter {
    static let meetingFolder: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm"
        return f
    }()
}
