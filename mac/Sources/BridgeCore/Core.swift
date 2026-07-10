import Foundation
import DeviceLinkProtocol

// ---- LinkLogger (CC-PRIV / SECURITY-03) ----

public enum LogLevel { case debug, info, warn, error }

public enum LinkLogger {
    private static let forbidden: Set<String> = ["body", "text", "number", "address", "contact", "token", "payload", "message"]
    public static var sink: (LogLevel, String, [String: String]) -> Void = { level, event, fields in
        print("[\(level)] \(event) \(fields.map { "\($0)=\($1)" }.joined(separator: ","))")
    }
    public static func log(_ level: LogLevel, _ event: String, _ fields: [String: String] = [:]) {
        sink(level, event, fields.filter { !forbidden.contains($0.key.lowercased()) })
    }
    public static func info(_ event: String, _ fields: [String: String] = [:]) { log(.info, event, fields) }
    public static func securityEvent(_ event: String, _ fields: [String: String] = [:]) { log(.warn, "security.\(event)", fields) }
    public static func redact(_ fields: [String: String]) -> [String: String] {
        fields.filter { !forbidden.contains($0.key.lowercased()) }
    }
}

// ---- SecureStore ----

public protocol SecureStore: AnyObject {
    func put(_ key: String, _ value: String)
    func get(_ key: String) -> String?
    func delete(_ key: String)
}

public final class InMemorySecureStore: SecureStore {
    private var map: [String: String] = [:]
    public init() {}
    public func put(_ key: String, _ value: String) { map[key] = value }
    public func get(_ key: String) -> String? { map[key] }
    public func delete(_ key: String) { map.removeValue(forKey: key) }
}

// ---- MessageRouter (fail-closed, SECURITY-15) ----

public final class MessageRouter {
    private var handlers: [String: (Message) -> Void] = [:]

    public init() {}

    public func register(_ type: String, _ handler: @escaping (Message) -> Void) {
        precondition(MessageTypes.known.contains(type), "cannot register unknown type: \(type)")
        handlers[type] = handler
    }

    public func unregister(_ type: String) { handlers.removeValue(forKey: type) }
    public func registeredTypes() -> Set<String> { Set(handlers.keys) }

    @discardableResult
    public func route(_ message: Message) -> Bool {
        if let err = validate(message) {
            LinkLogger.securityEvent("dropped_invalid", ["type": message.type, "reason": "\(err)"])
            return false
        }
        guard let handler = handlers[message.type] else {
            LinkLogger.securityEvent("dropped_unrouted", ["type": message.type])
            return false
        }
        handler(message)
        return true
    }
}

// ---- PluginRegistry (U10) ----

public enum FeatureId: String, CaseIterable { case notifications, sms, files, clipboard, screen, calls }

public final class PluginRegistry {
    private var enabledSet: Set<FeatureId>
    public init(enabled: Set<FeatureId> = Set(FeatureId.allCases)) { self.enabledSet = enabled }
    public func enable(_ id: FeatureId) { enabledSet.insert(id) }
    public func disable(_ id: FeatureId) { enabledSet.remove(id) }
    public func isEnabled(_ id: FeatureId) -> Bool { enabledSet.contains(id) }
    public func enabled() -> Set<FeatureId> { enabledSet }
}

// ---- Connection state machine (FR-2.3/2.4) ----

public enum ConnectionState { case disconnected, discovering, connecting, connected, reconnecting }

public final class ConnectionStateMachine {
    public enum Event { case startDiscovery, peerFound, connected, linkDropped, disconnectRequested }
    public private(set) var state: ConnectionState
    public init(_ initial: ConnectionState = .disconnected) { self.state = initial }

    @discardableResult
    public func onEvent(_ event: Event) -> ConnectionState {
        switch event {
        case .startDiscovery: state = .discovering
        case .peerFound: if state == .discovering || state == .reconnecting { state = .connecting }
        case .connected: state = .connected
        case .linkDropped: if state == .connected { state = .reconnecting }
        case .disconnectRequested: state = .disconnected
        }
        return state
    }
}
