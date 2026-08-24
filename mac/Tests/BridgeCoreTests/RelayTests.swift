import XCTest
import Foundation
@testable import BridgeCore
import DeviceLinkProtocol

final class RelayEndpointTests: XCTestCase {
    func testDerivesEnrollmentInvitationAndWebSocketURLs() throws {
        let endpoint = try RelayEndpoint(URL(string: "https://relay.example/base")!)

        XCTAssertEqual(endpoint.setupEnrollmentURL.absoluteString, "https://relay.example/base/v1/enrollment/setup")
        XCTAssertEqual(endpoint.invitationURL.absoluteString, "https://relay.example/base/v1/invitations")
        XCTAssertEqual(endpoint.webSocketURL.absoluteString, "wss://relay.example/base/v1/connect")
    }

    func testRejectsInsecureAndCredentialBearingEndpoints() {
        XCTAssertThrowsError(try RelayEndpoint(URL(string: "http://relay.example")!))
        XCTAssertThrowsError(try RelayEndpoint(URL(string: "https://user:pass@relay.example")!))
    }
}

final class RelayEnrollmentClientTests: XCTestCase {
    override func tearDown() {
        RelayURLProtocol.handler = nil
        super.tearDown()
    }

    func testSetupEnrollmentUsesBoundedHTTPSJSONRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayURLProtocol.self]
        let client = RelayEnrollmentClient(session: URLSession(configuration: configuration))
        RelayURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://relay.example/v1/enrollment/setup")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as? [String: String]
            XCTAssertEqual(body?["workspaceId"], "home")
            XCTAssertEqual(body?["deviceId"], "mac-1")
            XCTAssertEqual(body?["deviceType"], "MAC")
            XCTAssertEqual(body?["setupCode"], "one-time")
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(#"{"deviceId":"mac-1","credential":"secret"}"#.utf8))
        }

        let credential = try await client.enrollSetup(
            endpoint: RelayEndpoint(URL(string: "https://relay.example")!),
            workspaceId: "home",
            deviceId: "mac-1",
            setupCode: "one-time"
        )

        XCTAssertEqual(credential, RelayCredential(deviceId: "mac-1", credential: "secret"))
    }

    func testInvitationUsesEnrolledCredential() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayURLProtocol.self]
        let client = RelayEnrollmentClient(session: URLSession(configuration: configuration))
        RelayURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://relay.example/v1/invitations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-Id"), "mac-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(#"{"invitation":"invite","expiresAt":"soon"}"#.utf8))
        }

        let invitation = try await client.createPhoneInvitation(
            endpoint: RelayEndpoint(URL(string: "https://relay.example")!),
            credential: RelayCredential(deviceId: "mac-1", credential: "secret")
        )

        XCTAssertEqual(invitation.invitation, "invite")
        XCTAssertEqual(invitation.expiresAt, "soon")
    }
}

final class URLSessionRelayTransportTests: XCTestCase {
    func testWebSocketRequestUsesWSSAndCredentialHeaders() throws {
        let endpoint = try RelayEndpoint(URL(string: "https://relay.example")!)
        let request = URLSessionRelayTransport.request(
            endpoint: endpoint,
            credential: RelayCredential(deviceId: "mac-1", credential: "secret")
        )

        XCTAssertEqual(request.url?.absoluteString, "wss://relay.example/v1/connect")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-Id"), "mac-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }
}

final class RelaySettingsTests: XCTestCase {
    func testSettingsRoundTripThroughInjectedStore() throws {
        let persistence = MemoryRelaySettingsPersistence()
        let store = RelaySettingsStore(persistence: persistence)
        let settings = RelaySettings(enabled: true, endpoint: "https://relay.example", workspaceId: "home", deviceId: "mac-1", credential: "secret")

        try store.save(settings)

        XCTAssertEqual(try store.load(), settings)
        XCTAssertFalse(String(data: try XCTUnwrap(persistence.value), encoding: .utf8)!.contains("setupCode"))
    }
}

final class DirectFirstRelayPolicyTests: XCTestCase {
    func testRelayFallbackIsBoundedAndOldGenerationsAreRejected() {
        let policy = DirectFirstRelayPolicy(fallbackDelay: 6)
        let first = policy.begin(relayEnabled: true)
        XCTAssertEqual(first.fallbackDelay, 6)
        XCTAssertTrue(policy.isCurrent(first.generation))

        policy.directConnected()
        XCTAssertFalse(policy.isCurrent(first.generation))

        let disabled = policy.begin(relayEnabled: false)
        XCTAssertNil(disabled.fallbackDelay)
    }

    func testSleepInvalidatesGenerationAndWakeStartsFreshSession() {
        let policy = DirectFirstRelayPolicy(fallbackDelay: 6)
        let beforeSleep = policy.begin(relayEnabled: true)
        policy.suspend()
        XCTAssertFalse(policy.isCurrent(beforeSleep.generation))
        let afterWake = policy.begin(relayEnabled: true)
        XCTAssertNotEqual(afterWake.generation, beforeSleep.generation)
    }
}

final class RelayReplaySessionTests: XCTestCase {
    func testApplicationSupportJournalReplaysDurableSuffixAndAcknowledges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try DurableSyncJournal(rootURL: root, actorId: "mac")
        let replay = RelayReplaySession(journal: journal, actorId: "mac", peerActorId: "phone")
        let durable = Message(id: "event-1", type: MessageTypes.notifPosted, payload: ["title": .string("hello")])

        let frames = try replay.enqueue(durable)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertEqual(try journal.pending().map(\.messageType), [MessageTypes.notifPosted])

        let resumed = RelayReplaySession(journal: try DurableSyncJournal(rootURL: root, actorId: "mac"), actorId: "mac", peerActorId: "phone")
        XCTAssertFalse(try resumed.sessionFrames().isEmpty)
        let acknowledgement = SyncAcknowledgement(cursor: SyncCursor(actorId: "mac", throughSequence: 1), operationId: "event-1")
        _ = try resumed.handle(syncMessage(type: MessageTypes.syncAck, model: acknowledgement))
        XCTAssertTrue(try DurableSyncJournal(rootURL: root, actorId: "mac").pending().isEmpty)
    }

    func testIncomingOperationAppliesOnceThenReturnsAck() throws {
        let senderRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let receiverRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: senderRoot)
            try? FileManager.default.removeItem(at: receiverRoot)
        }
        let sender = RelayReplaySession(journal: try DurableSyncJournal(rootURL: senderRoot, actorId: "phone"), actorId: "phone", peerActorId: "mac")
        let receiver = RelayReplaySession(journal: try DurableSyncJournal(rootURL: receiverRoot, actorId: "mac"), actorId: "mac", peerActorId: "phone")
        let original = Message(id: "event-1", type: MessageTypes.smsReceived, payload: ["body": .string("hi")])
        var delivered: [Message] = []

        for frame in try sender.enqueue(original) {
            let message = try MessageCodec.decode([UInt8](frame))
            let result = try receiver.handle(message)
            delivered.append(contentsOf: result.messages)
        }

        XCTAssertEqual(delivered, [original])
        XCTAssertEqual(try receiver.journal.receivedThrough(actorId: "phone"), 1)

        var duplicateDelivery: [Message] = []
        for frame in try sender.sessionFrames().dropFirst(2) {
            let result = try receiver.handle(MessageCodec.decode([UInt8](frame)))
            duplicateDelivery.append(contentsOf: result.messages)
        }
        XCTAssertTrue(duplicateDelivery.isEmpty)
        XCTAssertEqual(try receiver.journal.receivedThrough(actorId: "phone"), 1)
    }
}

final class BoundedControlReceiverTests: XCTestCase {
    func testOversizedDeclaredLengthFailsBeforeBufferGrowth() {
        let receiver = BoundedControlReceiver()
        var header = [UInt8](repeating: 0, count: 4)
        writeU32BE(&header, 0, UInt32(ProtocolConstants.maxControlBytes + 1))

        XCTAssertThrowsError(try receiver.ingest(Data(header))) {
            XCTAssertEqual($0 as? ProtocolError, .oversize)
        }
        XCTAssertEqual(receiver.bufferedByteCount, 0)
    }
}

private final class MemoryRelaySettingsPersistence: RelaySettingsPersisting {
    var value: Data?
    func read() throws -> Data? { value }
    func write(_ data: Data) throws { value = data }
    func delete() throws { value = nil }
}

private final class RelayURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func syncMessage<T: Encodable>(type: String, model: T) throws -> Message {
    try RelaySyncMessageCodec.message(type: type, model: model)
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? RelayError.invalidResponse }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}
