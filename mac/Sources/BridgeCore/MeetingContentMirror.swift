import Foundation

/// Projects meeting text and validated photos into the Syncthing-backed Second Brain.
public struct MeetingContentMirror {
    private static let marker = "<!-- generated-by: android-bridge-meeting-sync -->"
    private let root: URL?
    private let fileManager = FileManager.default

    public init(root: URL? = nil) {
        self.root = root
    }

    public func sync(_ meetings: [MeetingRecord]) throws {
        let directory = brainRoot.appendingPathComponent("meetings/android-bridge", isDirectory: true)
        let photos = directory.appendingPathComponent("photos", isDirectory: true)
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try writeIndex(to: directory.appendingPathComponent("index.md"))
        let expected = Set(meetings.map { fileName(for: $0) })
        for meeting in meetings {
            let photoPaths = try syncPhotos(for: meeting, in: photos)
            try writeIfChanged(render(meeting, photoPaths: photoPaths), to: directory.appendingPathComponent(fileName(for: meeting)))
        }
        try removeStaleGeneratedNotes(in: directory, keeping: expected)
        try removeStalePhotoDirectories(in: photos, keeping: Set(meetings.map { slug($0.id) }))
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

    private func render(_ meeting: MeetingRecord, photoPaths: [String]) -> String {
        let company = meeting.company.isEmpty ? "Not assigned" : mobileSafe(meeting.company)
        var sections = [
            Self.marker,
            "# \(mobileSafe(meeting.title))",
            "",
            "- Date: \(meeting.date.formatted(date: .long, time: .shortened))",
            "- Company: \(company)",
            "- Status: \(meeting.processingState.rawValue)",
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
        if !photoPaths.isEmpty {
            sections += ["", "## Photos", ""]
            sections += photoPaths.enumerated().map { "![Meeting photo \($0.offset + 1)](\($0.element))" }
        }
        return sections.joined(separator: "\n") + "\n"
    }

    private func syncPhotos(for meeting: MeetingRecord, in photoRoot: URL) throws -> [String] {
        let meetingSlug = slug(meeting.id)
        let directory = photoRoot.appendingPathComponent(meetingSlug, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var expected: Set<String> = []
        var paths: [String] = []
        for image in meeting.imageFiles {
            let data = try Data(contentsOf: image)
            let ext = image.pathExtension.lowercased()
            let name = String(format: "photo-%03d.%@", paths.count + 1, ext)
            let path = "meetings/android-bridge/photos/\(meetingSlug)/\(name)"
            guard SecondBrainStore.mediaType(path: path, data: data) != nil else { continue }
            try writeIfChanged(data, to: directory.appendingPathComponent(name))
            expected.insert(name)
            paths.append("photos/\(meetingSlug)/\(name)")
        }
        for file in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where !expected.contains(file.lastPathComponent) {
            try fileManager.removeItem(at: file)
        }
        return paths
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
        try writeIfChanged(Data(text.utf8), to: url)
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
    }

    private func removeStaleGeneratedNotes(in directory: URL, keeping expected: Set<String>) throws {
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "md" && file.lastPathComponent != "index.md" && !expected.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.hasPrefix(Self.marker) { try fileManager.removeItem(at: file) }
        }
    }

    private func removeStalePhotoDirectories(in directory: URL, keeping expected: Set<String>) throws {
        let candidates = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        for candidate in candidates where !expected.contains(candidate.lastPathComponent) {
            if try candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try fileManager.removeItem(at: candidate)
            }
        }
    }
}
