import Foundation
import DeviceLinkProtocol

// ---- Stream chunking/reassembly (U6/U8, PROTOCOL.md §5) ----

public enum StreamChunker {
    public static func chunk(streamId: UInt32, data: Data, chunkSize: Int = ProtocolConstants.defaultChunkBytes) -> [Frame] {
        precondition(chunkSize > 0)
        if data.isEmpty {
            return [Frame(header: FrameHeader(streamId: streamId, sequence: 0, length: 0, flags: ProtocolConstants.flagEndOfStream), payload: Data())]
        }
        var frames: [Frame] = []
        var seq: UInt32 = 0
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let slice = data.subdata(in: offset..<end)
            let isLast = end == data.count
            let flags = isLast ? ProtocolConstants.flagEndOfStream : 0
            frames.append(Frame(header: FrameHeader(streamId: streamId, sequence: seq, length: slice.count, flags: flags), payload: slice))
            seq += 1
            offset = end
        }
        return frames
    }
}

public final class StreamReassembler {
    private let streamId: UInt32
    private var buffer = Data()
    private var expectedSeq: UInt32 = 0
    public private(set) var complete = false

    public init(streamId: UInt32) { self.streamId = streamId }

    @discardableResult
    public func accept(_ frame: Frame) -> Bool {
        if complete { return false }
        if frame.header.streamId != streamId { return fault("wrong_stream") }
        if frame.header.sequence != expectedSeq { return fault("sequence_gap") }
        buffer.append(frame.payload)
        expectedSeq += 1
        if frame.header.isEndOfStream { complete = true }
        return true
    }

    public func result() -> Data { buffer }

    private func fault(_ reason: String) -> Bool {
        LinkLogger.securityEvent("stream_faulted", ["streamId": "\(streamId)", "reason": reason])
        return false
    }
}

// ---- Clipboard sync (U7) — default MANUAL ----

public enum ClipboardSyncMode { case manual, auto }

public final class ClipboardSyncPolicy {
    public var mode: ClipboardSyncMode
    public init(_ mode: ClipboardSyncMode = .manual) { self.mode = mode }
    public func shouldSend(userInitiated: Bool) -> Bool {
        switch mode {
        case .auto: return true
        case .manual: return userInitiated
        }
    }
}

// ---- Mappers (OS domain → protocol Message) ----

public enum Mappers {
    public static func notification(pkg: String, title: String, text: String, postedAt: Int) -> Message {
        Message(id: UUID().uuidString, type: MessageTypes.notifPosted,
                payload: ["pkg": .string(pkg), "title": .string(title), "text": .string(text), "postedAt": .int(postedAt)])
    }
    public static func smsReceived(threadId: Int, address: String, body: String, receivedAt: Int) -> Message {
        Message(id: UUID().uuidString, type: MessageTypes.smsReceived,
                payload: ["threadId": .int(threadId), "address": .string(address), "body": .string(body), "receivedAt": .int(receivedAt)])
    }
    public static func incomingCall(number: String, contactName: String?) -> Message {
        var payload: [String: JSONValue] = ["number": .string(number)]
        if let n = contactName { payload["contactName"] = .string(n) }
        return Message(id: UUID().uuidString, type: MessageTypes.callIncoming, payload: payload)
    }
    public static func callAction(_ action: String, number: String? = nil) -> Message {
        var payload: [String: JSONValue] = ["action": .string(action)]
        if let n = number { payload["number"] = .string(n) }
        return Message(id: UUID().uuidString, type: MessageTypes.callAction, payload: payload)
    }
    public static func clipboard(_ text: String) -> Message {
        Message(id: UUID().uuidString, type: MessageTypes.clipUpdate, payload: ["text": .string(text)])
    }
    public static func screenRequest() -> Message {
        Message(id: UUID().uuidString, type: MessageTypes.screenRequest)
    }
    public static func inputTap(x: Double, y: Double, w: Double, h: Double) -> Message {
        Message(id: UUID().uuidString, type: MessageTypes.inputTap,
                payload: ["x": .double(x), "y": .double(y), "w": .double(w), "h": .double(h)])
    }
    public static func inputSwipe(x1: Double, y1: Double, x2: Double, y2: Double, w: Double, h: Double) -> Message {
        Message(id: UUID().uuidString, type: MessageTypes.inputSwipe,
                payload: ["x1": .double(x1), "y1": .double(y1), "x2": .double(x2), "y2": .double(y2), "w": .double(w), "h": .double(h)])
    }
}
