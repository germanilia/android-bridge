import AppKit
import Combine
import Foundation
import OSLog
import BridgeCore

@MainActor
final class MacUpdateController: ObservableObject {
    @Published private(set) var status = "Ready to check for updates."
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var availableUpdate: MacUpdate?
    @Published private(set) var verifiedUpdate: VerifiedMacUpdate?
    @Published var showConsent = false
    @Published var showError = false
    @Published var showGuidance = false
    @Published private(set) var errorMessage = ""

    private let service: MacUpdateService
    private let installedVersion: String
    private var automaticCheckStarted = false
    private var task: Task<Void, Never>?
    private let securityLogger = Logger(subsystem: "com.germanilia.android-bridge", category: "security")

    init(service: MacUpdateService = MacUpdateService(), bundle: Bundle = .main) {
        self.service = service
        installedVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var installedVersionText: String { installedVersion }

    func startAutomaticCheck() {
        guard !automaticCheckStarted else { return }
        automaticCheckStarted = true
        check(automatic: true)
    }

    func checkManually() {
        task?.cancel()
        check(automatic: false)
    }

    func approveDownload() {
        guard let update = availableUpdate else { return }
        showConsent = false
        task?.cancel()
        isDownloading = true
        status = "Downloading Android Bridge \(update.version)…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let verified = try await service.downloadAndVerify(update)
                guard !Task.isCancelled else {
                    removeAfterCancellation(verified)
                    return
                }
                downloadCompleted(verified)
            } catch {
                guard !Task.isCancelled else { return }
                downloadFailed(error)
            }
        }
    }

    func cancelDownload() {
        task?.cancel()
        isDownloading = false
        status = "Update download cancelled."
    }

    func openVerifiedUpdate() {
        guard let verified = verifiedUpdate else { return }
        if NSWorkspace.shared.open(verified.fileURL) {
            status = "Opened the verified update disk image."
            showGuidance = true
        } else {
            status = "macOS could not open the verified disk image."
            NSWorkspace.shared.activateFileViewerSelecting([verified.fileURL])
            errorMessage = "The verified disk image was revealed in Finder. Open it there, or download the release again."
            showError = true
        }
    }

    func revealVerifiedUpdate() {
        guard let verified = verifiedUpdate else { return }
        NSWorkspace.shared.activateFileViewerSelecting([verified.fileURL])
    }

    func cleanup() {
        task?.cancel()
        task = nil
        guard let verified = verifiedUpdate else { return }
        do { try service.removeTemporaryUpdate(verified) }
        catch { securityLogger.error("update_cleanup_failed") }
        verifiedUpdate = nil
    }

    private func check(automatic: Bool) {
        isChecking = true
        status = automatic ? "Checking for updates…" : "Checking GitHub for updates…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let update = try await service.check(currentVersion: installedVersion)
                guard !Task.isCancelled else { return }
                checkCompleted(update, automatic: automatic)
            } catch {
                guard !Task.isCancelled else { return }
                checkFailed(error, automatic: automatic)
            }
        }
    }

    private func checkCompleted(_ update: MacUpdate?, automatic: Bool) {
        isChecking = false
        availableUpdate = update
        guard let update else {
            status = "Android Bridge is up to date (\(installedVersion))."
            return
        }
        status = "Android Bridge \(update.version) is available."
        if automatic { showConsent = true }
    }

    private func checkFailed(_ error: Error, automatic: Bool) {
        isChecking = false
        status = automatic ? "Update check unavailable." : "Could not check for updates."
        if automatic {
            if error is MacUpdateError { securityLogger.error("update_metadata_rejected") }
            return
        }
        present(error)
    }

    private func downloadCompleted(_ update: VerifiedMacUpdate) {
        isDownloading = false
        verifiedUpdate = update
        status = "Android Bridge \(update.update.version) was verified and is ready to open."
        openVerifiedUpdate()
    }

    private func removeAfterCancellation(_ update: VerifiedMacUpdate) {
        do { try service.removeTemporaryUpdate(update) }
        catch { securityLogger.error("update_cleanup_failed") }
    }

    private func downloadFailed(_ error: Error) {
        isDownloading = false
        status = "Update download failed."
        present(error)
    }

    private func present(_ error: Error) {
        errorMessage = (error as? MacUpdateError)?.localizedDescription ?? "The update could not be completed safely."
        showError = true
    }
}
