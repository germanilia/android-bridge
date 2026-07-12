import Foundation

public enum SetupDependencyID: String, CaseIterable, Sendable {
    case homebrew, ffmpeg, python, whisper, ollama, ollamaModel, node, pi
}

public struct SetupDependency: Identifiable, Equatable, Sendable {
    public let id: SetupDependencyID
    public let name: String
    public let purpose: String
    public let installProgram: String
    public let installArguments: [String]

    public init(id: SetupDependencyID, name: String, purpose: String, installProgram: String, installArguments: [String]) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.installProgram = installProgram
        self.installArguments = installArguments
    }
}

public enum SetupDependencyState: Equatable, Sendable {
    case checking
    case missing
    case installed(String)
    case installing
    case failed(String)
}

public enum SetupCatalog {
    public static let defaultModel = "gemma4:e4b"

    public static func dependencies(applicationSupport: URL, requirements: URL?) -> [SetupDependency] {
        let venv = applicationSupport.appendingPathComponent("mlx-whisper", isDirectory: true)
        let python = venv.appendingPathComponent("bin/python").path
        let requirementsPath = requirements?.path ?? ""
        return [
            .init(id: .homebrew, name: "Homebrew", purpose: "Installs the remaining command-line tools from maintained packages.", installProgram: "/bin/bash", installArguments: ["-c", "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""]),
            .init(id: .ffmpeg, name: "ffmpeg", purpose: "Converts meeting audio before transcription.", installProgram: "/usr/bin/env", installArguments: ["brew", "install", "ffmpeg"]),
            .init(id: .python, name: "Python", purpose: "Runs the local MLX Whisper transcription environment.", installProgram: "/usr/bin/env", installArguments: ["brew", "install", "python"]),
            .init(id: .whisper, name: "MLX Whisper", purpose: "Transcribes meetings locally on Apple Silicon.", installProgram: "/bin/bash", installArguments: ["-c", "\"$(command -v python3)\" -m venv \"\(venv.path)\" && \"\(python)\" -m pip install -r \"\(requirementsPath)\""]),
            .init(id: .ollama, name: "Ollama", purpose: "Runs local language models for summaries and chat.", installProgram: "/usr/bin/env", installArguments: ["brew", "install", "--cask", "ollama"]),
            .init(id: .ollamaModel, name: defaultModel, purpose: "Default local model for Android Bridge AI features.", installProgram: "/bin/bash", installArguments: ["-c", "open -a Ollama && sleep 5 && ollama pull \(defaultModel)"]),
            .init(id: .node, name: "Node.js", purpose: "Required to install and run pi.", installProgram: "/usr/bin/env", installArguments: ["brew", "install", "node"]),
            .init(id: .pi, name: "pi", purpose: "Optional model-routed assistant used by Second Brain tasks.", installProgram: "/usr/bin/env", installArguments: ["npm", "install", "-g", "@earendil-works/pi-coding-agent"]),
        ]
    }
}

public final class SetupDetector: @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationSupport: URL
    private let bundledWhisperPython: URL?

    public init(fileManager: FileManager = .default, applicationSupport: URL, bundledWhisperPython: URL? = nil) {
        self.fileManager = fileManager
        self.applicationSupport = applicationSupport
        self.bundledWhisperPython = bundledWhisperPython
    }

    public func state(for id: SetupDependencyID) -> SetupDependencyState {
        switch id {
        case .homebrew: return executableState("brew")
        case .ffmpeg: return executableState("ffmpeg")
        case .python: return executableState("python3")
        case .ollama: return executableState("ollama")
        case .node: return executableState("node")
        case .pi: return executableState("pi")
        case .whisper:
            let managedPython = applicationSupport.appendingPathComponent("mlx-whisper/bin/python")
            if fileManager.isExecutableFile(atPath: managedPython.path) { return .installed(managedPython.path) }
            if let bundledWhisperPython, fileManager.isExecutableFile(atPath: bundledWhisperPython.path) {
                return .installed(bundledWhisperPython.path)
            }
            return .missing
        case .ollamaModel:
            return commandOutput("ollama", ["list"]).contains(SetupCatalog.defaultModel) ? .installed(SetupCatalog.defaultModel) : .missing
        }
    }

    private func executableState(_ name: String) -> SetupDependencyState {
        let output = commandOutput("which", [name]).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? .missing : .installed(output)
    }

    private func commandOutput(_ command: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.environment = setupProcessEnvironment()
        process.arguments = [command] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

public func setupProcessEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
    return environment
}
