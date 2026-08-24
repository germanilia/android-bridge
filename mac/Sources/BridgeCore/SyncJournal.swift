import Foundation
import Crypto
import DeviceLinkProtocol

public enum ContentHash {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum SyncJournalError: Error, Equatable {
    case cursorRegression
    case cursorBeyondHighWater
    case staleCursor
    case sequenceGap
    case operationIdCollision
    case digestMismatch
    case invalidChunk
    case incompleteTransfer
    case invalidOperation
}

public enum IncomingDisposition: Equatable { case apply, duplicate, gap }

private struct ReceivedOperation: Codable {
    let actorId: String
    let sequence: Int64
}

private struct JournalState: Codable {
    let actorId: String
    var highWater: Int64 = 0
    var acknowledgedThrough: Int64 = 0
    var operations: [SyncOperation] = []
    var localOperationIds: Set<String> = []
    var receivedCursors: [String: Int64] = [:]
    var receivedOperations: [String: ReceivedOperation] = [:]
}

public final class DurableSyncJournal {
    private let stateURL: URL
    private let blobURL: URL
    private let actorId: String
    private let lock = NSLock()
    private let incomingApplyLock = NSLock()
    private var state: JournalState
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public init(rootURL: URL, actorId: String) throws {
        precondition(!actorId.isEmpty)
        self.stateURL = rootURL.appendingPathComponent("journal.json")
        self.blobURL = rootURL.appendingPathComponent("blobs", isDirectory: true)
        self.actorId = actorId
        try FileManager.default.createDirectory(at: self.blobURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: self.stateURL.path) {
            self.state = try JSONDecoder().decode(JournalState.self, from: Data(contentsOf: self.stateURL))
        } else {
            self.state = JournalState(actorId: actorId)
        }
        precondition(state.actorId == actorId, "journal actor mismatch")
        try validateLoadedState()
    }

    public var highWater: Int64 { withLock { state.highWater } }
    public var acknowledgedThrough: Int64 { withLock { state.acknowledgedThrough } }

    @discardableResult
    public func enqueue(
        operationId: String,
        kind: SyncOperationKind,
        target: String,
        content: Data?,
        baseDigest: String? = nil,
        messageType: String? = nil,
        mediaType: String? = nil
    ) throws -> SyncOperation {
        try withLock {
            try validateMutation(operationId: operationId, kind: kind, target: target, content: content, messageType: messageType)
            if state.localOperationIds.contains(operationId) { throw SyncJournalError.operationIdCollision }
            let digest = try content.map { data -> String in
                let hash = ContentHash.sha256(data)
                try storeBlob(digest: hash, data: data)
                return hash
            }
            let operation = SyncOperation(
                operationId: operationId,
                actorId: actorId,
                sequence: state.highWater + 1,
                kind: kind,
                target: target,
                messageType: messageType,
                baseDigest: baseDigest,
                resultDigest: digest,
                blobDigest: digest,
                byteCount: Int64(content?.count ?? 0),
                mediaType: mediaType
            )
            var next = state
            next.highWater = operation.sequence
            next.operations.append(operation)
            next.localOperationIds.insert(operationId)
            try commit(next)
            return operation
        }
    }

    public func pending() throws -> [SyncOperation] { withLock { state.operations } }

    public func pending(after sequence: Int64) throws -> [SyncOperation] {
        try withLock {
            if sequence < state.acknowledgedThrough { throw SyncJournalError.staleCursor }
            if sequence > state.highWater { throw SyncJournalError.cursorBeyondHighWater }
            return state.operations.filter { $0.sequence > sequence }
        }
    }

    public func acknowledge(through sequence: Int64) throws {
        try withLock {
            if sequence < state.acknowledgedThrough { throw SyncJournalError.cursorRegression }
            if sequence > state.highWater { throw SyncJournalError.cursorBeyondHighWater }
            if sequence == state.acknowledgedThrough { return }
            var next = state
            next.acknowledgedThrough = sequence
            next.operations.removeAll { $0.sequence <= sequence }
            try commit(next)
            try pruneUnreferencedBlobs()
        }
    }

    public func incomingDisposition(_ operation: SyncOperation) throws -> IncomingDisposition {
        try withLock { try disposition(operation) }
    }

    @discardableResult
    public func recordApplied(_ operation: SyncOperation) throws -> Bool {
        try recordApplied(operation, durableApply: {})
    }

    @discardableResult
    public func recordApplied(_ operation: SyncOperation, durableApply: () throws -> Void) throws -> Bool {
        incomingApplyLock.lock()
        defer { incomingApplyLock.unlock() }
        switch try withLock({ try disposition(operation) }) {
        case .duplicate:
            return false
        case .gap:
            throw SyncJournalError.sequenceGap
        case .apply:
            try durableApply()
            return try withLock {
                var next = state
                next.receivedCursors[operation.actorId] = operation.sequence
                next.receivedOperations[operation.operationId] = ReceivedOperation(actorId: operation.actorId, sequence: operation.sequence)
                try commit(next)
                return true
            }
        }
    }

    public func receivedThrough(actorId: String) throws -> Int64 {
        withLock { state.receivedCursors[actorId] ?? 0 }
    }

    public func readBlob(digest: String) throws -> Data {
        try withLock { try readBlobUnlocked(digest: digest) }
    }

    private func readBlobUnlocked(digest: String) throws -> Data {
        guard digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw SyncJournalError.digestMismatch
        }
        let data = try Data(contentsOf: blobURL.appendingPathComponent(digest))
        guard ContentHash.sha256(data) == digest else { throw SyncJournalError.digestMismatch }
        return data
    }

    private func disposition(_ operation: SyncOperation) throws -> IncomingDisposition {
        if let seen = state.receivedOperations[operation.operationId] {
            guard seen.actorId == operation.actorId, seen.sequence == operation.sequence else {
                throw SyncJournalError.operationIdCollision
            }
            return .duplicate
        }
        let cursor = state.receivedCursors[operation.actorId] ?? 0
        if operation.sequence <= cursor { throw SyncJournalError.staleCursor }
        return operation.sequence == cursor + 1 ? .apply : .gap
    }

    private func validateMutation(
        operationId: String,
        kind: SyncOperationKind,
        target: String,
        content: Data?,
        messageType: String?
    ) throws {
        let invalid = operationId.isEmpty || target.isEmpty ||
            (kind == .tombstone && content != nil) ||
            (kind != .tombstone && content == nil) ||
            (kind == .message && messageType == nil)
        if invalid { throw SyncJournalError.invalidOperation }
    }

    private func validateLoadedState() throws {
        precondition(state.acknowledgedThrough >= 0 && state.acknowledgedThrough <= state.highWater)
        precondition(zip(state.operations, state.operations.dropFirst()).allSatisfy { $0.1.sequence == $0.0.sequence + 1 })
        precondition(state.operations.isEmpty || state.operations.first?.sequence == state.acknowledgedThrough + 1)
        precondition(state.operations.isEmpty || state.operations.last?.sequence == state.highWater)
        precondition(state.operations.allSatisfy { $0.actorId == actorId && $0.sequence > state.acknowledgedThrough })
        for digest in state.operations.compactMap(\.blobDigest) { _ = try readBlobUnlocked(digest: digest) }
    }

    private func storeBlob(digest: String, data: Data) throws {
        let destination = blobURL.appendingPathComponent(digest)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == data else { throw SyncJournalError.digestMismatch }
            return
        }
        try data.write(to: destination, options: .atomic)
    }

    private func commit(_ next: JournalState) throws {
        try encoder.encode(next).write(to: stateURL, options: .atomic)
        state = next
    }

    private func pruneUnreferencedBlobs() throws {
        let retained = Set(state.operations.compactMap(\.blobDigest))
        let blobs = try FileManager.default.contentsOfDirectory(at: blobURL, includingPropertiesForKeys: nil)
        for blob in blobs where !retained.contains(blob.lastPathComponent) {
            try FileManager.default.removeItem(at: blob)
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

public struct NoteConflictResolution: Equatable {
    public let outcome: ConflictOutcome
    public let canonical: Data?
    public let conflict: Data?
}

public enum NoteConflictResolver {
    public static func resolve(current: Data?, incoming: Data?, baseDigest: String?) -> NoteConflictResolution {
        let currentDigest = current.map(ContentHash.sha256)
        let incomingDigest = incoming.map(ContentHash.sha256)
        if currentDigest == incomingDigest {
            return NoteConflictResolution(outcome: .unchanged, canonical: current, conflict: nil)
        }
        if currentDigest == baseDigest {
            let outcome: ConflictOutcome = incoming == nil ? .deleted : .applied
            return NoteConflictResolution(outcome: outcome, canonical: incoming, conflict: nil)
        }
        return NoteConflictResolution(outcome: .conflictPreserved, canonical: current, conflict: incoming)
    }
}

public enum SyncTransferChunker {
    public static func chunk(operationId: String, data: Data, chunkSize: Int) throws -> [TransferChunk] {
        guard (1...ProtocolConstants.maxFramePayloadBytes).contains(chunkSize) else {
            throw SyncJournalError.invalidChunk
        }
        if data.isEmpty { return [makeChunk(operationId: operationId, index: 0, offset: 0, data: Data(), final: true)] }
        var chunks: [TransferChunk] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let bytes = data.subdata(in: offset..<end)
            chunks.append(makeChunk(operationId: operationId, index: chunks.count, offset: Int64(offset), data: bytes, final: end == data.count))
            offset = end
        }
        return chunks
    }

    private static func makeChunk(operationId: String, index: Int, offset: Int64, data: Data, final: Bool) -> TransferChunk {
        TransferChunk(
            operationId: operationId,
            index: index,
            offset: offset,
            dataBase64: data.base64EncodedString(),
            digest: ContentHash.sha256(data),
            isFinal: final
        )
    }
}

public final class SyncTransferReassembler {
    private let operationId: String
    private let expectedDigest: String
    private var data = Data()
    private var nextIndex = 0
    private var complete = false

    public init(operationId: String, expectedDigest: String) {
        self.operationId = operationId
        self.expectedDigest = expectedDigest
    }

    public func accept(_ chunk: TransferChunk) throws {
        guard !complete,
              chunk.operationId == operationId,
              chunk.index == nextIndex,
              chunk.offset == Int64(data.count) else {
            throw SyncJournalError.invalidChunk
        }
        let bytes: Data
        do { bytes = try chunk.decodedData() } catch { throw SyncJournalError.invalidChunk }
        guard bytes.count <= ProtocolConstants.maxFramePayloadBytes,
              ContentHash.sha256(bytes) == chunk.digest else {
            throw SyncJournalError.digestMismatch
        }
        data.append(bytes)
        nextIndex += 1
        complete = chunk.isFinal
    }

    public func result() throws -> Data {
        guard complete else { throw SyncJournalError.incompleteTransfer }
        guard ContentHash.sha256(data) == expectedDigest else { throw SyncJournalError.digestMismatch }
        return data
    }
}
