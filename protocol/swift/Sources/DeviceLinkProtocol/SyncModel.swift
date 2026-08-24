import Foundation

public enum SyncCapability: String, Codable, Equatable, CaseIterable {
    case durableSync = "durable-sync-v1"
    case resumableTransfer = "resumable-transfer-v1"
    case noteConflicts = "note-conflicts-v1"
}

public struct CapabilityAnnouncement: Codable, Equatable {
    public let actorId: String
    public let capabilities: [SyncCapability]
    public init(actorId: String, capabilities: [SyncCapability]) {
        self.actorId = actorId
        self.capabilities = capabilities
    }
}

public struct SyncCursor: Codable, Equatable {
    public let actorId: String
    public let throughSequence: Int64

    public init(actorId: String, throughSequence: Int64) {
        precondition(!actorId.isEmpty && throughSequence >= 0)
        self.actorId = actorId
        self.throughSequence = throughSequence
    }

    public func advanced(to sequence: Int64) throws -> SyncCursor {
        guard sequence >= throughSequence else { throw SyncModelError.cursorRegression }
        return SyncCursor(actorId: actorId, throughSequence: sequence)
    }
}

public struct ResumeRequest: Codable, Equatable {
    public let cursor: SyncCursor
    public init(cursor: SyncCursor) { self.cursor = cursor }
}

public struct SyncAcknowledgement: Codable, Equatable {
    public let cursor: SyncCursor
    public let operationId: String
    public init(cursor: SyncCursor, operationId: String) {
        self.cursor = cursor
        self.operationId = operationId
    }
}

public enum SyncOperationKind: String, Codable, Equatable, CaseIterable {
    case message, snapshot, tombstone, transfer
}

public struct SyncOperation: Codable, Equatable {
    public let operationId: String
    public let actorId: String
    public let sequence: Int64
    public let kind: SyncOperationKind
    public let target: String
    public let messageType: String?
    public let baseDigest: String?
    public let resultDigest: String?
    public let blobDigest: String?
    public let byteCount: Int64
    public let mediaType: String?

    public init(
        operationId: String,
        actorId: String,
        sequence: Int64,
        kind: SyncOperationKind,
        target: String,
        messageType: String? = nil,
        baseDigest: String? = nil,
        resultDigest: String? = nil,
        blobDigest: String? = nil,
        byteCount: Int64 = 0,
        mediaType: String? = nil
    ) {
        self.operationId = operationId
        self.actorId = actorId
        self.sequence = sequence
        self.kind = kind
        self.target = target
        self.messageType = messageType
        self.baseDigest = baseDigest
        self.resultDigest = resultDigest
        self.blobDigest = blobDigest
        self.byteCount = byteCount
        self.mediaType = mediaType
    }
}

public enum ConflictOutcome: String, Codable, Equatable {
    case unchanged, applied, deleted, conflictPreserved
}

public struct TransferChunk: Codable, Equatable {
    public let operationId: String
    public let index: Int
    public let offset: Int64
    public let dataBase64: String
    public let digest: String
    public let isFinal: Bool

    public init(operationId: String, index: Int, offset: Int64, dataBase64: String, digest: String, isFinal: Bool) {
        self.operationId = operationId
        self.index = index
        self.offset = offset
        self.dataBase64 = dataBase64
        self.digest = digest
        self.isFinal = isFinal
    }

    public func decodedData() throws -> Data {
        guard let data = Data(base64Encoded: dataBase64) else { throw SyncModelError.malformedBase64 }
        return data
    }
}

public enum SyncModelError: Error, Equatable {
    case cursorRegression
    case malformedBase64
}

public enum SyncModelCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    public static func encode<T: Encodable>(_ value: T) throws -> Data { try encoder.encode(value) }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

public enum ReplayClassification: String, Codable, Equatable {
    case durable, coalesced, liveOnly
}

public enum ReplayClassifier {
    private static let durable: Set<String> = [
        MessageTypes.notifPosted, MessageTypes.smsReceived, MessageTypes.smsThread,
        MessageTypes.fileOffer, MessageTypes.fileProgress, MessageTypes.fileChunk,
        MessageTypes.meetingStart, MessageTypes.meetingStop,
        MessageTypes.meetingAudioChunkOffer, MessageTypes.meetingPhotoOffer,
        MessageTypes.meetingProcessingStatus, MessageTypes.meetingNotesReady,
    ]
    private static let coalesced: Set<String> = [MessageTypes.clipUpdate, MessageTypes.callState]
    private static let liveOnly: Set<String> = Set([
        MessageTypes.linkHello, MessageTypes.linkHeartbeat,
        MessageTypes.pairRequest, MessageTypes.pairResponse,
        MessageTypes.fileAccept,
        MessageTypes.screenStart, MessageTypes.screenStop, MessageTypes.screenFrame, MessageTypes.screenRequest,
        MessageTypes.inputTap, MessageTypes.inputSwipe,
        MessageTypes.callIncoming, MessageTypes.callAction, MessageTypes.callHistory,
        MessageTypes.meetingAudioChunkReceived, MessageTypes.meetingPhotoReceived,
    ]).union(MessageTypes.sync)

    public static func classify(_ messageType: String) throws -> ReplayClassification {
        guard MessageTypes.known.contains(messageType) else { throw ProtocolError.unknownType }
        if durable.contains(messageType) { return .durable }
        if coalesced.contains(messageType) { return .coalesced }
        if liveOnly.contains(messageType) { return .liveOnly }
        throw ProtocolError.schemaMismatch
    }
}
