import Foundation
import Security

/// The two levers Trusted Presence pulls, and the one secret it needs.
///
/// `keepAwake` needs no secret: holding the Mac awake is an ordinary app capability.
/// `disableLockPassword` does: `sysadminctl -screenLock` refuses to run without the
/// user's login password ("Password is required!"), so that password is stored in the
/// login Keychain. That is a real change to this app's security posture and the UI says so.
public enum ScreenLockControl {

    // MARK: - Awake hold (no secret required)

    private static var awakeToken: NSObjectProtocol?

    /// While held, the display never idles, so the Mac never reaches the lock screen.
    /// Closing the lid still sleeps and still locks normally — this only suppresses the
    /// *idle* path, which is why it is the safer of the two switches.
    public static func setAwakeHold(_ held: Bool, reason: String = "Trusted network or device is present") {
        if held {
            guard awakeToken == nil else { return }
            awakeToken = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                reason: reason
            )
        } else {
            guard let token = awakeToken else { return }
            ProcessInfo.processInfo.endActivity(token)
            awakeToken = nil
        }
    }

    public static var isHoldingAwake: Bool { awakeToken != nil }

    // MARK: - Lock password (requires the login password)

    public enum LockError: Error, LocalizedError {
        case noStoredPassword
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noStoredPassword:
                return "No login password saved. Add it in the Trusted Presence tab first."
            case .commandFailed(let message):
                return "sysadminctl failed: \(message)"
            }
        }
    }

    /// True when waking the Mac currently asks for a password.
    public static func requiresPassword() -> Bool {
        let result = runSysadminctl(["-screenLock", "status"], password: nil)
        return !result.succeeded || !result.output.lowercased().contains("is off")
    }

    /// `required == false` turns the wake password prompt off; `true` restores it immediately.
    public static func setPasswordRequired(_ required: Bool, store: LoginPasswordStore = LoginPasswordStore()) throws {
        guard let password = try store.read() else { throw LockError.noStoredPassword }
        let result = runSysadminctl(["-screenLock", required ? "immediate" : "off"], password: password)
        guard result.succeeded,
              !result.output.contains("Password is required"),
              !result.output.lowercased().contains("error") else {
            throw LockError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Verifies a password by asking sysadminctl to set the lock state it is already in —
    /// a no-op that still fails loudly on a wrong password.
    public static func verify(password: String) -> Bool {
        let current = requiresPassword() ? "immediate" : "off"
        let result = runSysadminctl(["-screenLock", current], password: password)
        return result.succeeded && !result.output.contains("Password is required") &&
            !result.output.lowercased().contains("error")
    }

    /// The password goes in on stdin rather than in the argument list, so it never appears
    /// in `ps` output for other processes on this Mac.
    private static func runSysadminctl(_ arguments: [String], password: String?) -> (output: String, succeeded: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
        process.arguments = password == nil ? arguments : arguments + ["-password", "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let input = Pipe()
        process.standardInput = input

        do {
            try process.run()
        } catch {
            return (error.localizedDescription, false)
        }
        if let password {
            input.fileHandleForWriting.write(Data((password + "\n").utf8))
        }
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus == 0)
    }
}

/// The user's macOS login password, in the login Keychain.
/// Same shape as `KeychainRelaySettingsPersistence` so there is one Keychain idiom in this app.
public final class LoginPasswordStore {
    private let service: String
    private let account: String

    public init(service: String = "com.androidbridge.trustedpresence", account: String = "loginPassword") {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ password: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    public var exists: Bool { ((try? read()) ?? nil) != nil }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public enum KeychainError: Error { case status(OSStatus) }
}
