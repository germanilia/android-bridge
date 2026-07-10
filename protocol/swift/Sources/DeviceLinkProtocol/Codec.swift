import Foundation

@inline(__always)
public func writeU32BE(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
    buf[off] = UInt8((v >> 24) & 0xFF)
    buf[off + 1] = UInt8((v >> 16) & 0xFF)
    buf[off + 2] = UInt8((v >> 8) & 0xFF)
    buf[off + 3] = UInt8(v & 0xFF)
}

@inline(__always)
public func readU32BE(_ buf: [UInt8], _ off: Int) -> UInt32 {
    (UInt32(buf[off]) << 24) | (UInt32(buf[off + 1]) << 16) | (UInt32(buf[off + 2]) << 8) | UInt32(buf[off + 3])
}

/// Validate an inbound message — PROTOCOL.md §4.
public func validate(_ message: Message) -> ProtocolError? {
    if message.protocolVersion != ProtocolConstants.version { return .versionMismatch }
    if !MessageTypes.known.contains(message.type) { return .unknownType }
    if message.id.isEmpty { return .schemaMismatch }
    return nil
}

/// Length-prefixed JSON control codec — PROTOCOL.md §3–§4.
public enum MessageCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    public static func encode(_ message: Message) throws -> [UInt8] {
        let body = [UInt8](try encoder.encode(message))
        if body.count > ProtocolConstants.maxControlBytes { throw ProtocolError.oversize }
        var out = [UInt8](repeating: 0, count: 4 + body.count)
        writeU32BE(&out, 0, UInt32(body.count))
        for i in 0..<body.count { out[4 + i] = body[i] }
        return out
    }

    public static func decode(_ bytes: [UInt8]) throws -> Message {
        try decodeNext(bytes, 0).0
    }

    public static func decodeNext(_ bytes: [UInt8], _ offset: Int) throws -> (Message, Int) {
        if bytes.count - offset < 4 { throw ProtocolError.malformedLength }
        let len = Int(readU32BE(bytes, offset))
        if len > ProtocolConstants.maxControlBytes { throw ProtocolError.oversize }
        let start = offset + 4
        if bytes.count - start < len { throw ProtocolError.malformedLength }
        let slice = Data(bytes[start..<(start + len)])
        let message: Message
        do {
            message = try decoder.decode(Message.self, from: slice)
        } catch {
            throw ProtocolError.malformedJSON
        }
        if let err = validate(message) { throw err }
        return (message, start + len)
    }

    public static func decodeStream(_ bytes: [UInt8]) throws -> [Message] {
        var out: [Message] = []
        var off = 0
        while off < bytes.count {
            let (m, next) = try decodeNext(bytes, off)
            out.append(m)
            off = next
        }
        return out
    }
}

/// Binary frame codec — PROTOCOL.md §5.
public enum FrameCodec {
    public static func encodeFrame(_ header: FrameHeader, _ payload: Data) throws -> [UInt8] {
        if payload.count != header.length { throw ProtocolError.badFrameHeader }
        var out = [UInt8](repeating: 0, count: ProtocolConstants.frameHeaderBytes + payload.count)
        writeU32BE(&out, 0, header.streamId)
        writeU32BE(&out, 4, header.sequence)
        writeU32BE(&out, 8, UInt32(header.length))
        out[12] = UInt8(header.flags & 0xFF)
        let p = [UInt8](payload)
        for i in 0..<p.count { out[ProtocolConstants.frameHeaderBytes + i] = p[i] }
        return out
    }

    public static func decodeFrame(_ bytes: [UInt8]) throws -> Frame {
        if bytes.count < ProtocolConstants.frameHeaderBytes { throw ProtocolError.badFrameHeader }
        let streamId = readU32BE(bytes, 0)
        let sequence = readU32BE(bytes, 4)
        let length = Int(readU32BE(bytes, 8))
        let flags = Int(bytes[12])
        if bytes.count - ProtocolConstants.frameHeaderBytes < length { throw ProtocolError.badFrameHeader }
        let payload = Data(bytes[ProtocolConstants.frameHeaderBytes..<(ProtocolConstants.frameHeaderBytes + length)])
        return Frame(header: FrameHeader(streamId: streamId, sequence: sequence, length: length, flags: flags), payload: payload)
    }
}
