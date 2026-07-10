import Foundation

// Protocol constants — see protocol/PROTOCOL.md §9.
public enum ProtocolConstants {
    public static let version = 1
    public static let maxControlBytes = 1_048_576 // 1 MiB
    public static let defaultChunkBytes = 65_536 // 64 KiB
    public static let inlineBlobMaxBytes = 32_768 // 32 KiB
    public static let flagEndOfStream = 0x01
    public static let frameHeaderBytes = 13
}

/// A JSON value, modeling the per-type `payload`. Equatable + Codable for exact round-trips.
public indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Control message envelope — PROTOCOL.md §2. Custom Codable applies defaults for absent keys.
public struct Message: Equatable {
    public let id: String
    public let type: String
    public let protocolVersion: Int
    public let replyTo: String?
    public let payload: [String: JSONValue]

    public init(
        id: String,
        type: String,
        protocolVersion: Int = ProtocolConstants.version,
        replyTo: String? = nil,
        payload: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.protocolVersion = protocolVersion
        self.replyTo = replyTo
        self.payload = payload
    }
}

extension Message: Codable {
    enum CodingKeys: String, CodingKey { case id, type, protocolVersion, replyTo, payload }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        protocolVersion = try c.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? ProtocolConstants.version
        replyTo = try c.decodeIfPresent(String.self, forKey: .replyTo)
        payload = try c.decodeIfPresent([String: JSONValue].self, forKey: .payload) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        if protocolVersion != ProtocolConstants.version { try c.encode(protocolVersion, forKey: .protocolVersion) }
        try c.encodeIfPresent(replyTo, forKey: .replyTo)
        if !payload.isEmpty { try c.encode(payload, forKey: .payload) }
    }
}

/// Binary frame header — PROTOCOL.md §5. `streamId`/`sequence` are unsigned 32-bit.
public struct FrameHeader: Equatable {
    public let streamId: UInt32
    public let sequence: UInt32
    public let length: Int
    public let flags: Int

    public init(streamId: UInt32, sequence: UInt32, length: Int, flags: Int) {
        self.streamId = streamId
        self.sequence = sequence
        self.length = length
        self.flags = flags
    }

    public var isEndOfStream: Bool { (flags & ProtocolConstants.flagEndOfStream) != 0 }
}

public struct Frame: Equatable {
    public let header: FrameHeader
    public let payload: Data
    public init(header: FrameHeader, payload: Data) {
        self.header = header
        self.payload = payload
    }
}

/// Typed protocol failures — PROTOCOL.md §4. Carries no payload content (CC-PRIV).
public enum ProtocolError: Error, Equatable {
    case malformedLength
    case malformedJSON
    case oversize
    case unknownType
    case schemaMismatch
    case badFrameHeader
    case versionMismatch
}

/// Message type registry — PROTOCOL.md §6.
public enum MessageTypes {
    public static let linkHello = "link.hello"
    public static let linkHeartbeat = "link.heartbeat"
    public static let pairRequest = "pair.request"
    public static let pairResponse = "pair.response"
    public static let notifPosted = "notif.posted"
    public static let smsReceived = "sms.received"
    public static let smsThread = "sms.thread"
    public static let fileOffer = "file.offer"
    public static let fileAccept = "file.accept"
    public static let fileProgress = "file.progress"
    public static let fileChunk = "file.chunk"
    public static let clipUpdate = "clip.update"
    public static let screenStart = "screen.start"
    public static let screenStop = "screen.stop"
    public static let screenFrame = "screen.frame"
    public static let screenRequest = "screen.request"
    public static let inputTap = "input.tap"
    public static let inputSwipe = "input.swipe"
    public static let callIncoming = "call.incoming"
    public static let callAction = "call.action"
    public static let callState = "call.state"
    public static let callHistory = "call.history"
    public static let meetingStart = "meeting.start"
    public static let meetingStop = "meeting.stop"
    public static let meetingAudioChunkOffer = "meeting.audioChunk.offer"
    public static let meetingAudioChunkReceived = "meeting.audioChunk.received"
    public static let meetingPhotoOffer = "meeting.photo.offer"
    public static let meetingPhotoReceived = "meeting.photo.received"
    public static let meetingProcessingStatus = "meeting.processing.status"
    public static let meetingNotesReady = "meeting.notes.ready"

    public static let known: Set<String> = [
        linkHello, linkHeartbeat, pairRequest, pairResponse,
        notifPosted, smsReceived, smsThread,
        fileOffer, fileAccept, fileProgress, fileChunk,
        clipUpdate, screenStart, screenStop, screenFrame, screenRequest,
        inputTap, inputSwipe, callIncoming, callAction, callState, callHistory,
        meetingStart, meetingStop, meetingAudioChunkOffer, meetingAudioChunkReceived,
        meetingPhotoOffer, meetingPhotoReceived, meetingProcessingStatus, meetingNotesReady,
    ]
}
