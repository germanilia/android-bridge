import Foundation
import Security
import DeviceLinkProtocol

public enum RelayError: Error, Equatable, LocalizedError {
    case invalidEndpoint
    case insecureEndpoint
    case invalidResponse
    case responseTooLarge
    case httpStatus(Int)
    case keychain(OSStatus)
    case notEnrolled
    case transportUnavailable
    case unexpectedMessage

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Enter a valid relay endpoint."
        case .insecureEndpoint: return "Relay endpoints must use HTTPS."
        case .invalidResponse: return "The relay returned an invalid response."
        case .responseTooLarge: return "The relay response exceeded the size limit."
        case .httpStatus(let status): return "The relay returned HTTP \(status)."
        case .keychain(let status): return "Keychain operation failed with status \(status)."
        case .notEnrolled: return "Enroll this Mac before enabling relay access."
        case .transportUnavailable: return "The relay connection is unavailable."
        case .unexpectedMessage: return "The relay sent an unexpected synchronization message."
        }
    }
}

public struct RelayEndpoint: Equatable {
    public let baseURL: URL

    public init(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else { throw RelayError.insecureEndpoint }
        guard url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw RelayError.invalidEndpoint
        }
        baseURL = url
    }

    public var setupEnrollmentURL: URL { baseURL.appendingPathComponent("v1/enrollment/setup") }
    public var invitationURL: URL { baseURL.appendingPathComponent("v1/invitations") }
    public var webSocketURL: URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/connect"), resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        return components.url!
    }
}

public struct RelayCredential: Codable, Equatable, Sendable {
    public let deviceId: String
    public let credential: String

    public init(deviceId: String, credential: String) {
        self.deviceId = deviceId
        self.credential = credential
    }
}

public struct RelayInvitation: Codable, Equatable, Sendable {
    public let invitation: String
    public let expiresAt: String
}

private final class RelayRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public final class RelayEnrollmentClient {
    private struct SetupRequest: Encodable {
        let workspaceId: String
        let deviceId: String
        let deviceType = "MAC"
        let setupCode: String
    }
    private struct InvitationRequest: Encodable { let deviceType = "PHONE" }

    private static let defaultSession = URLSession(
        configuration: .ephemeral,
        delegate: RelayRedirectRejectingDelegate(),
        delegateQueue: nil
    )
    private let session: URLSession
    private let maximumResponseBytes = 65_536
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(session: URLSession? = nil) { self.session = session ?? Self.defaultSession }

    public func enrollSetup(
        endpoint: RelayEndpoint,
        workspaceId: String,
        deviceId: String,
        setupCode: String
    ) async throws -> RelayCredential {
        let body = SetupRequest(workspaceId: workspaceId, deviceId: deviceId, setupCode: setupCode)
        return try await post(endpoint.setupEnrollmentURL, body: body, credential: nil, response: RelayCredential.self)
    }

    public func createPhoneInvitation(endpoint: RelayEndpoint, credential: RelayCredential) async throws -> RelayInvitation {
        try await post(endpoint.invitationURL, body: InvitationRequest(), credential: credential, response: RelayInvitation.self)
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ url: URL,
        body: Request,
        credential: RelayCredential?,
        response: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        if let credential {
            request.setValue(credential.deviceId, forHTTPHeaderField: "X-Device-Id")
            request.setValue("Bearer \(credential.credential)", forHTTPHeaderField: "Authorization")
        }
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, http.url == url else { throw RelayError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw RelayError.httpStatus(http.statusCode) }
        guard data.count <= maximumResponseBytes else { throw RelayError.responseTooLarge }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw RelayError.invalidResponse }
    }
}

public struct RelaySettings: Codable, Equatable {
    public var enabled: Bool
    public var endpoint: String
    public var workspaceId: String
    public var deviceId: String
    public var credential: String?

    public init(enabled: Bool, endpoint: String, workspaceId: String, deviceId: String, credential: String? = nil) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.workspaceId = workspaceId
        self.deviceId = deviceId
        self.credential = credential
    }

    public var isEnrolled: Bool { credential?.isEmpty == false }
}

public protocol RelaySettingsPersisting: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

public final class KeychainRelaySettingsPersistence: RelaySettingsPersisting {
    private let service: String
    private let account: String

    public init(service: String = "com.androidbridge.relay", account: String = "settings") {
        self.service = service
        self.account = account
    }

    public func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw RelayError.keychain(status) }
        return data
    }

    public func write(_ data: Data) throws {
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw RelayError.keychain(status) }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw RelayError.keychain(addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RelayError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public final class RelaySettingsStore {
    private let persistence: RelaySettingsPersisting
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(persistence: RelaySettingsPersisting = KeychainRelaySettingsPersistence()) {
        self.persistence = persistence
    }

    public func load() throws -> RelaySettings? {
        guard let data = try persistence.read() else { return nil }
        return try decoder.decode(RelaySettings.self, from: data)
    }

    public func save(_ settings: RelaySettings) throws { try persistence.write(encoder.encode(settings)) }
    public func delete() throws { try persistence.delete() }
}

public struct RelaySessionPlan: Equatable {
    public let generation: UInt64
    public let fallbackDelay: TimeInterval?
}

public final class DirectFirstRelayPolicy {
    public let fallbackDelay: TimeInterval
    private let lock = NSLock()
    private var generation: UInt64 = 0

    public init(fallbackDelay: TimeInterval = 6) {
        precondition(fallbackDelay > 0)
        self.fallbackDelay = fallbackDelay
    }

    public func begin(relayEnabled: Bool) -> RelaySessionPlan {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return RelaySessionPlan(generation: generation, fallbackDelay: relayEnabled ? fallbackDelay : nil)
    }

    public func directConnected() { invalidate() }
    public func suspend() { invalidate() }

    public func isCurrent(_ candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return candidate == generation
    }

    private func invalidate() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }
}

public enum RelayTransportState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

public protocol RelayTransporting: AnyObject {
    var onState: ((RelayTransportState, UInt64) -> Void)? { get set }
    var onFrame: ((Data, UInt64) -> Void)? { get set }
    func connect(endpoint: RelayEndpoint, credential: RelayCredential, generation: UInt64)
    func send(_ data: Data) throws
    func disconnect()
}

public final class URLSessionRelayTransport: NSObject, RelayTransporting, URLSessionWebSocketDelegate {
    public var onState: ((RelayTransportState, UInt64) -> Void)?
    public var onFrame: ((Data, UInt64) -> Void)?

    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var generation: UInt64 = 0

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public static func request(endpoint: RelayEndpoint, credential: RelayCredential) -> URLRequest {
        var request = URLRequest(url: endpoint.webSocketURL)
        request.timeoutInterval = 15
        request.setValue(credential.deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue("Bearer \(credential.credential)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func connect(endpoint: RelayEndpoint, credential: RelayCredential, generation: UInt64) {
        disconnect()
        let next = session.webSocketTask(with: Self.request(endpoint: endpoint, credential: credential))
        lock.lock()
        self.generation = generation
        task = next
        lock.unlock()
        onState?(.connecting, generation)
        next.resume()
    }

    public func send(_ data: Data) throws {
        lock.lock()
        let current = task
        lock.unlock()
        guard let current else { throw RelayError.transportUnavailable }
        current.send(.data(data)) { [weak self, weak current] error in
            guard let self, let error, let current else { return }
            self.fail(error.localizedDescription, task: current)
        }
    }

    public func disconnect() {
        lock.lock()
        let current = task
        task = nil
        let oldGeneration = generation
        lock.unlock()
        current?.cancel(with: .goingAway, reason: nil)
        if current != nil { onState?(.disconnected, oldGeneration) }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard let currentGeneration = currentGeneration(for: webSocketTask) else { return }
        onState?(.connected, currentGeneration)
        receive(on: webSocketTask, generation: currentGeneration)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard let currentGeneration = clearIfCurrent(webSocketTask) else { return }
        onState?(.disconnected, currentGeneration)
    }

    private func receive(on task: URLSessionWebSocketTask, generation: UInt64) {
        task.receive { [weak self, weak task] result in
            guard let self, let task, self.currentGeneration(for: task) == generation else { return }
            switch result {
            case .success(.data(let data)):
                guard data.count <= ProtocolConstants.maxControlBytes + 4 else {
                    task.cancel(with: .messageTooBig, reason: nil)
                    self.fail(RelayError.responseTooLarge.localizedDescription, task: task)
                    return
                }
                self.onFrame?(data, generation)
                self.receive(on: task, generation: generation)
            case .success(.string(let message)):
                self.fail(String(message.prefix(256)), task: task)
            case .failure(let error):
                self.fail(error.localizedDescription, task: task)
            @unknown default:
                self.fail(RelayError.unexpectedMessage.localizedDescription, task: task)
            }
        }
    }

    private func fail(_ message: String, task: URLSessionWebSocketTask) {
        guard let currentGeneration = clearIfCurrent(task) else { return }
        task.cancel(with: .goingAway, reason: nil)
        onState?(.failed(message), currentGeneration)
    }

    private func currentGeneration(for candidate: URLSessionWebSocketTask) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return task === candidate ? generation : nil
    }

    private func clearIfCurrent(_ candidate: URLSessionWebSocketTask) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard task === candidate else { return nil }
        task = nil
        return generation
    }
}

public enum RelaySyncMessageCodec {
    public static func message<T: Encodable>(type: String, model: T) throws -> Message {
        let data = try SyncModelCodec.encode(model)
        let payload = try JSONDecoder().decode([String: JSONValue].self, from: data)
        return Message(id: UUID().uuidString, type: type, payload: payload)
    }

    public static func model<T: Decodable>(_ type: T.Type, from message: Message) throws -> T {
        try SyncModelCodec.decode(type, from: JSONEncoder().encode(message.payload))
    }

    public static func frame(_ message: Message) throws -> Data { Data(try MessageCodec.encode(message)) }
}

public struct RelayReplayResult {
    public let messages: [Message]
    public let outboundFrames: [Data]

    public init(messages: [Message] = [], outboundFrames: [Data] = []) {
        self.messages = messages
        self.outboundFrames = outboundFrames
    }
}

public final class RelayReplaySession {
    public let journal: DurableSyncJournal
    public let actorId: String
    public let peerActorId: String
    private var incomingOperations: [String: SyncOperation] = [:]
    private var reassemblers: [String: SyncTransferReassembler] = [:]
    private var ignoredIncomingOperationIds: Set<String> = []

    public init(journal: DurableSyncJournal, actorId: String, peerActorId: String) {
        self.journal = journal
        self.actorId = actorId
        self.peerActorId = peerActorId
    }

    public static func applicationSupport(actorId: String, peerActorId: String = "phone") throws -> RelayReplaySession {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("AndroidBridge/RelaySync", isDirectory: true)
        return RelayReplaySession(journal: try DurableSyncJournal(rootURL: root, actorId: actorId), actorId: actorId, peerActorId: peerActorId)
    }

    public func enqueue(_ message: Message) throws -> [Data] {
        guard try ReplayClassifier.classify(message.type) != .liveOnly else {
            return [try RelaySyncMessageCodec.frame(message)]
        }
        let bytes = Data(try MessageCodec.encode(message))
        let operation = try journal.enqueue(
            operationId: message.id,
            kind: .message,
            target: message.id,
            content: bytes,
            messageType: message.type,
            mediaType: "application/vnd.androidbridge.message"
        )
        return try operationFrames(operation)
    }

    public func sessionFrames() throws -> [Data] {
        let capabilities = CapabilityAnnouncement(actorId: actorId, capabilities: [.durableSync, .resumableTransfer])
        let received = try journal.receivedThrough(actorId: peerActorId)
        let resume = ResumeRequest(cursor: SyncCursor(actorId: peerActorId, throughSequence: received))
        var frames = [
            try RelaySyncMessageCodec.frame(RelaySyncMessageCodec.message(type: MessageTypes.syncCapabilities, model: capabilities)),
            try RelaySyncMessageCodec.frame(RelaySyncMessageCodec.message(type: MessageTypes.syncResume, model: resume)),
        ]
        for operation in try journal.pending() { frames.append(contentsOf: try operationFrames(operation)) }
        return frames
    }

    public func handle(_ message: Message) throws -> RelayReplayResult {
        switch message.type {
        case MessageTypes.syncAck:
            let acknowledgement = try RelaySyncMessageCodec.model(SyncAcknowledgement.self, from: message)
            try apply(acknowledgement)
            return RelayReplayResult()
        case MessageTypes.syncResume:
            let request = try RelaySyncMessageCodec.model(ResumeRequest.self, from: message)
            guard request.cursor.actorId == actorId else { throw RelayError.unexpectedMessage }
            var frames: [Data] = []
            for operation in try journal.pending(after: request.cursor.throughSequence) {
                frames.append(contentsOf: try operationFrames(operation))
            }
            return RelayReplayResult(outboundFrames: frames)
        case MessageTypes.syncOperation:
            return try accept(try RelaySyncMessageCodec.model(SyncOperation.self, from: message))
        case MessageTypes.syncTransferChunk:
            return try accept(try RelaySyncMessageCodec.model(TransferChunk.self, from: message))
        case MessageTypes.syncCapabilities:
            _ = try RelaySyncMessageCodec.model(CapabilityAnnouncement.self, from: message)
            return RelayReplayResult()
        default:
            return RelayReplayResult(messages: [message])
        }
    }

    private func apply(_ acknowledgement: SyncAcknowledgement) throws {
        guard acknowledgement.cursor.actorId == actorId else { throw RelayError.unexpectedMessage }
        if acknowledgement.cursor.throughSequence <= journal.acknowledgedThrough { return }
        guard let operation = try journal.pending().first(where: { $0.sequence == acknowledgement.cursor.throughSequence }),
              operation.operationId == acknowledgement.operationId else { throw RelayError.unexpectedMessage }
        try journal.acknowledge(through: acknowledgement.cursor.throughSequence)
    }

    private func accept(_ operation: SyncOperation) throws -> RelayReplayResult {
        switch try journal.incomingDisposition(operation) {
        case .duplicate:
            ignoredIncomingOperationIds.insert(operation.operationId)
            return RelayReplayResult(outboundFrames: [try acknowledgementFrame(operation)])
        case .gap:
            ignoredIncomingOperationIds.insert(operation.operationId)
            let cursor = try journal.receivedThrough(actorId: operation.actorId)
            let resume = ResumeRequest(cursor: SyncCursor(actorId: operation.actorId, throughSequence: cursor))
            return RelayReplayResult(outboundFrames: [try RelaySyncMessageCodec.frame(RelaySyncMessageCodec.message(type: MessageTypes.syncResume, model: resume))])
        case .apply:
            guard operation.kind == .message, operation.actorId == peerActorId,
                  operation.blobDigest != nil, operation.resultDigest != nil else {
                throw RelayError.unexpectedMessage
            }
            incomingOperations[operation.operationId] = operation
            reassemblers[operation.operationId] = SyncTransferReassembler(
                operationId: operation.operationId,
                expectedDigest: operation.resultDigest!
            )
            return RelayReplayResult()
        }
    }

    private func accept(_ chunk: TransferChunk) throws -> RelayReplayResult {
        if ignoredIncomingOperationIds.contains(chunk.operationId) {
            if chunk.isFinal { ignoredIncomingOperationIds.remove(chunk.operationId) }
            return RelayReplayResult()
        }
        guard let operation = incomingOperations[chunk.operationId], let reassembler = reassemblers[chunk.operationId] else {
            throw RelayError.unexpectedMessage
        }
        try reassembler.accept(chunk)
        guard chunk.isFinal else { return RelayReplayResult() }
        let bytes = try reassembler.result()
        let original = try MessageCodec.decode([UInt8](bytes))
        guard original.type == operation.messageType else { throw RelayError.unexpectedMessage }
        let apply = try journal.recordApplied(operation)
        incomingOperations.removeValue(forKey: chunk.operationId)
        reassemblers.removeValue(forKey: chunk.operationId)
        return RelayReplayResult(
            messages: apply ? [original] : [],
            outboundFrames: [try acknowledgementFrame(operation)]
        )
    }

    private func operationFrames(_ operation: SyncOperation) throws -> [Data] {
        var frames = [try RelaySyncMessageCodec.frame(RelaySyncMessageCodec.message(type: MessageTypes.syncOperation, model: operation))]
        if let digest = operation.blobDigest {
            let data = try journal.readBlob(digest: digest)
            for chunk in try SyncTransferChunker.chunk(operationId: operation.operationId, data: data, chunkSize: ProtocolConstants.inlineBlobMaxBytes) {
                frames.append(try RelaySyncMessageCodec.frame(RelaySyncMessageCodec.message(type: MessageTypes.syncTransferChunk, model: chunk)))
            }
        }
        return frames
    }

    private func acknowledgementFrame(_ operation: SyncOperation) throws -> Data {
        let acknowledgement = SyncAcknowledgement(
            cursor: SyncCursor(actorId: operation.actorId, throughSequence: operation.sequence),
            operationId: operation.operationId
        )
        return try RelaySyncMessageCodec.frame(RelaySyncMessageCodec.message(type: MessageTypes.syncAck, model: acknowledgement))
    }
}

public final class BoundedControlReceiver {
    private let decoder = ControlStreamDecoder()
    public init() {}
    public var bufferedByteCount: Int { decoder.bufferedByteCount }
    public func ingest(_ data: Data) throws -> [Message] { try decoder.ingest([UInt8](data)) }
}
