import Foundation

/// Projects meeting text into the Syncthing-backed Second Brain without copying media.
public struct MeetingContentMirror {
    private static let marker = "<!-- generated-by: android-bridge-meeting-sync -->"
    private let root: URL?
    private let fileManager = FileManager.default

    public init(root: URL? = nil) {
        self.root = root
    }

    public func sync(_ meetings: [MeetingRecord]) throws {
        let directory = brainRoot.appendingPathComponent("meetings/android-bridge", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeIndex(to: directory.appendingPathComponent("index.md"))
        let expected = Set(meetings.map { fileName(for: $0) })
        for meeting in meetings {
            try writeIfChanged(render(meeting), to: directory.appendingPathComponent(fileName(for: meeting)))
        }
        try removeStaleGeneratedNotes(in: directory, keeping: expected)
    }

    private var brainRoot: URL {
        root ?? SecondBrainStore().rootURL
    }

    private func writeIndex(to url: URL) throws {
        let text = """
        \(Self.marker)
        # Meetings

        Meeting summaries and transcripts synced from Android Bridge. Recordings stay on the Mac.
        """
        try writeIfChanged(text + "\n", to: url)
    }

    private func render(_ meeting: MeetingRecord) -> String {
        let company = meeting.company.isEmpty ? "Not assigned" : mobileSafe(meeting.company)
        let recordings = meeting.audioCount == 1
            ? "1 file kept on this Mac"
            : "\(meeting.audioCount) files kept on this Mac"
        var sections = [
            Self.marker,
            "# \(mobileSafe(meeting.title))",
            "",
            "- Date: \(meeting.date.formatted(date: .long, time: .shortened))",
            "- Company: \(company)",
            "- Status: \(meeting.processingState.rawValue)",
            "- Recordings: \(recordings)",
            "",
            "## Summary",
            "",
            meeting.summary.isEmpty ? "No summary yet." : mobileSafe(meeting.summary),
        ]
        if !meeting.transcript.isEmpty {
            sections += ["", "## Transcript", "", mobileSafe(meeting.transcript)]
        }
        if !meeting.questions.isEmpty {
            sections += ["", "## Q&A", "", mobileSafe(meeting.questions)]
        }
        return sections.joined(separator: "\n") + "\n"
    }

    private func mobileSafe(_ text: String) -> String {
        let withoutPlaceholders = text.components(separatedBy: .newlines)
            .filter { !$0.contains(MeetingStore.untranscribedMarker) }
            .joined(separator: "\n")
        let replacements = [
            (#"/Users/[^\s)\]]+"#, "[local recording omitted]"),
            (#"(?m)(^|\s)/[^\s)\]]+"#, "$1[local recording omitted]"),
            (#"(?i)[^\s]+\.(?:m4a|wav|3gp)"#, "[local recording omitted]"),
        ]
        return replacements.reduce(withoutPlaceholders) { value, replacement in
            guard let regex = try? NSRegularExpression(pattern: replacement.0) else { return value }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement.1)
        }
    }

    private func fileName(for meeting: MeetingRecord) -> String {
        "\(slug(meeting.id)).md"
    }

    private func slug(_ value: String) -> String {
        var result = ""
        var separatorPending = false
        for character in value.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if separatorPending && !result.isEmpty { result.append("-") }
                result.append(character)
                separatorPending = false
            } else {
                separatorPending = true
            }
        }
        return result.isEmpty ? "meeting" : result
    }

    private func writeIfChanged(_ text: String, to url: URL) throws {
        if (try? String(contentsOf: url, encoding: .utf8)) == text { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeStaleGeneratedNotes(in directory: URL, keeping expected: Set<String>) throws {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "md" && file.lastPathComponent != "index.md" && !expected.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.hasPrefix(Self.marker) { try fileManager.removeItem(at: file) }
        }
    }
}
