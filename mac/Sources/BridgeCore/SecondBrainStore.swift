import Foundation

public struct BrainNode: Identifiable, Equatable {
    public let id: String
    public let path: String
    public let label: String
    public let isDirectory: Bool
    public let depth: Int
}

public struct BrainSearchResult: Identifiable, Equatable {
    public let id: String
    public let path: String
    public let title: String
    public let snippet: String
}

public struct BrainEdge: Identifiable, Equatable {
    public let id: String
    public let from: String
    public let to: String
    public let label: String
}

public final class SecondBrainStore {
    private let fm = FileManager.default
    private let scriptURL: URL
    public let rootURL: URL

    public init() {
        let home = fm.homeDirectoryForCurrentUser
        scriptURL = home.appendingPathComponent(".agents/skills/second-brain/scripts/brain.py")
        let configured = UserDefaults.standard.string(forKey: "secondBrain.root")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let env = ProcessInfo.processInfo.environment["BRAIN_ROOT"]?.trimmingCharacters(in: .whitespaces)
        rootURL = URL(fileURLWithPath: configured?.isEmpty == false ? configured! : (env?.isEmpty == false ? env! : home.appendingPathComponent("second_brain").path))
    }

    public func tree() throws -> [BrainNode] {
        let output = try run(["tree"])
        var stack = [String]()
        return output.components(separatedBy: .newlines).compactMap { parseTreeLine($0, stack: &stack) }
    }

    public func show(_ path: String) throws -> String {
        try run(["show", path.isEmpty ? "index.md" : path])
    }

    public func edges() -> [BrainEdge] {
        let files = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "md" }.flatMap { url in
            let rel = String(url.path.dropFirst(rootURL.path.count + 1))
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return links(in: text).map { link in
                let target = resolve(link.target, from: rel)
                return BrainEdge(id: "\(rel)->\(target)->\(link.title)", from: rel, to: target, label: link.title)
            }
        }
    }

    public func search(_ query: String) throws -> [BrainSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = LLMConfig.config(for: .secondBrainSearch)
        if config.usePi {
            let prompt = "Search my second brain for: \(clean). Return concise matching note paths and snippets."
            let answer = LLMService(feature: .secondBrainSearch).run(prompt, feature: .secondBrainSearch) ?? "No search results returned."
            return [BrainSearchResult(id: "pi", path: "index.md", title: "pi results", snippet: answer)]
        }
        return try localSearch(clean)
    }

    public func addCluster(parent: String, name: String, title: String, desc: String) throws {
        _ = try run(["add-cluster", "--parent", parent, "--name", name, "--title", title, "--desc", desc])
        _ = try run(["check"])
    }

    public func addNote(cluster: String, title: String, summary: String, tags: String, body: String) throws {
        _ = try run(["add-note", "--cluster", cluster, "--title", title, "--summary", summary, "--tags", tags], stdin: body)
        _ = try run(["check"])
    }

    public func save(path: String, content: String) throws {
        let url = rootURL.appendingPathComponent(path)
        try content.write(to: url, atomically: true, encoding: .utf8)
        _ = try run(["check"])
    }

    public func deleteNote(path: String) throws {
        _ = try run(["delete-note", path])
        _ = try run(["check"])
    }

    public func answer(path: String, question: String) throws -> String {
        let content = try show(path)
        let prompt = "Answer the question using only this second-brain node. If the answer is not present, say so briefly.\n\nNode path: \(path)\n\nNode content:\n\(content)\n\nQuestion: \(question)"
        return LLMService(feature: .secondBrainQA).run(prompt, feature: .secondBrainQA) ?? "No answer returned."
    }

    private func localSearch(_ query: String) throws -> [BrainSearchResult] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        let files = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "md" }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lower = text.lowercased()
            guard terms.allSatisfy({ lower.contains($0) }) else { return nil }
            let rel = String(url.path.dropFirst(rootURL.path.count + 1))
            return BrainSearchResult(id: rel, path: rel, title: title(from: text, fallback: url.deletingPathExtension().lastPathComponent), snippet: snippet(from: text, terms: terms))
        }.prefix(12).map { $0 }
    }

    private func title(from text: String, fallback: String) -> String {
        text.components(separatedBy: .newlines).first { $0.hasPrefix("# ") }?.replacingOccurrences(of: "# ", with: "") ?? fallback
    }

    private func snippet(from text: String, terms: [String]) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("---") && !$0.hasPrefix("tags:") }
        let matches = lines.filter { line in terms.contains { line.lowercased().contains($0) } }.prefix(3)
        let picked = matches.isEmpty ? lines.prefix(3) : matches
        return picked.map { compact($0) }.joined(separator: "\n")
    }

    private func compact(_ line: String) -> String {
        line.count > 260 ? String(line.prefix(260)) + "…" : line
    }

    private func links(in text: String) -> [(title: String, target: String)] {
        let pattern = #"\[([^\]]+)\]\(([^\)]+\.md)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges == 3 else { return nil }
            return (ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2)))
        }
    }

    private func resolve(_ target: String, from source: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        let base = (source as NSString).deletingLastPathComponent
        return URL(fileURLWithPath: base).appendingPathComponent(target).path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func run(_ arguments: [String], stdin: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["BRAIN_ROOT"] = rootURL.path
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let input = Pipe()
        process.standardInput = input
        try process.run()
        let writer = input.fileHandleForWriting
        DispatchQueue.global(qos: .utility).async {
            writer.write(Data((stdin ?? "").utf8))
            try? writer.close()
        }
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 0 { return String(data: data, encoding: .utf8) ?? "" }
        let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "brain.py failed"
        throw NSError(domain: "SecondBrain", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail])
    }

    private func parseTreeLine(_ line: String, stack: inout [String]) -> BrainNode? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "second_brain/" else { return nil }
        let marker = line.range(of: "├── ") ?? line.range(of: "└── ")
        guard let marker else { return nil }
        let label = String(line[marker.upperBound...])
        let depth = line.distance(from: line.startIndex, to: marker.lowerBound) / 4
        while stack.count > depth { stack.removeLast() }
        let isDirectory = label.hasSuffix("/")
        let name = isDirectory ? String(label.dropLast()) : label
        let path = (stack + [name]).joined(separator: "/") + (isDirectory ? "/index.md" : "")
        if isDirectory { stack.append(name) }
        return BrainNode(id: path, path: path, label: label, isDirectory: isDirectory, depth: depth)
    }
}
