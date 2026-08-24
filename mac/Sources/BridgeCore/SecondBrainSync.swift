import DeviceLinkProtocol
import Foundation

public enum SecondBrainSyncError: Error, Equatable {
    case invalidOperation
    case digestMismatch
    case handlerUnavailable
}

private struct SecondBrainManifestState: Codable {
    var hashes: [String: String]
}

public final class SecondBrainSyncManifest {
    private let stateURL: URL
    private let lock = NSLock()
    private var state: SecondBrainManifestState
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public init(rootURL: URL) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        stateURL = rootURL.appendingPathComponent("path-hashes.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            state = try JSONDecoder().decode(SecondBrainManifestState.self, from: Data(contentsOf: stateURL))
            try Self.validate(state.hashes)
        } else {
            state = SecondBrainManifestState(hashes: [:])
        }
    }

    public static func applicationSupport() throws -> SecondBrainSyncManifest {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try SecondBrainSyncManifest(rootURL: support.appendingPathComponent("AndroidBridge/RelaySync/SecondBrain", isDirectory: true))
    }

    public func entries() throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return state.hashes
    }

    public func replace(_ hashes: [String: String]) throws {
        lock.lock()
        defer { lock.unlock() }
        try Self.validate(hashes)
        let next = SecondBrainManifestState(hashes: hashes)
        try encoder.encode(next).write(to: stateURL, options: .atomic)
        state = next
    }

    private static func validate(_ hashes: [String: String]) throws {
        let valid = hashes.allSatisfy { path, digest in
            SecondBrainStore.isSyncablePath(path) && digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        }
        if !valid { throw SecondBrainSyncError.invalidOperation }
    }
}

public final class SecondBrainDeltaSynchronizer {
    private let store: SecondBrainStore
    private let manifest: SecondBrainSyncManifest
    private let replaySession: RelayReplaySession
    private let lock = NSLock()

    public init(store: SecondBrainStore, manifest: SecondBrainSyncManifest, replaySession: RelayReplaySession) {
        self.store = store
        self.manifest = manifest
        self.replaySession = replaySession
        replaySession.setSyncOperationHandlers(
            snapshot: { [weak self] operation, content in
                guard let self else { throw SecondBrainSyncError.handlerUnavailable }
                _ = try self.apply(operation, content: content)
            },
            tombstone: { [weak self] operation in
                guard let self else { throw SecondBrainSyncError.handlerUnavailable }
                _ = try self.apply(operation, content: nil)
            }
        )
    }

    public static func applicationSupport(store: SecondBrainStore, replaySession: RelayReplaySession) throws -> SecondBrainDeltaSynchronizer {
        SecondBrainDeltaSynchronizer(store: store, manifest: try .applicationSupport(), replaySession: replaySession)
    }

    public func scan() throws -> [Data] {
        try withLock {
            let files = try store.syncFiles()
            var known = try manifest.entries()
            var frames: [Data] = []
            let currentPaths = Set(files.map(\.path))

            for file in files where known[file.path] != file.digest {
                frames += try replaySession.enqueueSnapshot(
                    target: file.path,
                    content: file.data,
                    baseDigest: known[file.path],
                    mediaType: file.mediaType
                )
                known[file.path] = file.digest
                try manifest.replace(known)
            }
            for path in known.keys.sorted() where !currentPaths.contains(path) {
                frames += try replaySession.enqueueTombstone(target: path, baseDigest: known[path])
                known.removeValue(forKey: path)
                try manifest.replace(known)
            }
            return frames
        }
    }

    public func apply(_ operation: SyncOperation, content: Data?) throws -> SecondBrainApplyResult {
        try withLock {
            try validate(operation, content: content)
            let current = try store.syncData(path: operation.target)
            let resolution = NoteConflictResolver.resolve(current: current, incoming: content, baseDigest: operation.baseDigest)
            var hashes = try manifest.entries()
            var conflictPath: String?

            switch resolution.outcome {
            case .unchanged:
                break
            case .applied:
                try store.writeSyncData(path: operation.target, data: content!, mediaType: operation.mediaType!)
            case .deleted:
                try store.removeSyncData(path: operation.target)
            case .conflictPreserved:
                conflictPath = try preserveConflict(operation, content: content)
            }

            updateManifest(&hashes, path: operation.target, data: try store.syncData(path: operation.target))
            if let conflictPath {
                updateManifest(&hashes, path: conflictPath, data: try store.syncData(path: conflictPath))
            }
            try manifest.replace(hashes)
            return SecondBrainApplyResult(outcome: resolution.outcome, conflictPath: conflictPath)
        }
    }

    private func validate(_ operation: SyncOperation, content: Data?) throws {
        guard SecondBrainStore.isValidRelativePath(operation.target), operation.byteCount == Int64(content?.count ?? 0) else {
            throw SecondBrainSyncError.invalidOperation
        }
        switch operation.kind {
        case .snapshot:
            guard let content, let digest = operation.resultDigest,
                  operation.blobDigest == digest,
                  ContentHash.sha256(content) == digest,
                  let mediaType = operation.mediaType,
                  SecondBrainStore.mediaType(path: operation.target, data: content) == mediaType else {
                throw SecondBrainSyncError.digestMismatch
            }
        case .tombstone:
            guard content == nil, operation.resultDigest == nil, operation.blobDigest == nil,
                  operation.mediaType == nil, SecondBrainStore.isSyncablePath(operation.target) else {
                throw SecondBrainSyncError.invalidOperation
            }
        default:
            throw SecondBrainSyncError.invalidOperation
        }
    }

    private func preserveConflict(_ operation: SyncOperation, content: Data?) throws -> String {
        if let content {
            let path = try store.conflictPath(for: operation)
            try store.writeSyncData(path: path, data: content, mediaType: operation.mediaType!)
            return path
        }
        let path = try store.conflictPath(for: operation, deleted: true)
        let marker = Data("# Deletion conflict\n\nA remote edit deleted `\(operation.target)`, but this Mac has a newer local version. The local version was kept.\n".utf8)
        try store.writeSyncData(path: path, data: marker, mediaType: "text/markdown")
        return path
    }

    private func updateManifest(_ hashes: inout [String: String], path: String, data: Data?) {
        guard let data, SecondBrainStore.mediaType(path: path, data: data) != nil else {
            hashes.removeValue(forKey: path)
            return
        }
        hashes[path] = ContentHash.sha256(data)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
