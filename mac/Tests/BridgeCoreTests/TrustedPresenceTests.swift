import XCTest
@testable import BridgeCore

/// Trusted Presence decides whether the Mac is somewhere the user has marked safe.
/// The decision must be pure and total: same inputs, same answer, no I/O.
final class TrustedPresenceTests: XCTestCase {

    private let homeWifi = TrustedPlace(kind: .wifi, identifier: "cc:2d:21:5d:f2:e0", label: "Home")
    private let phone = TrustedPlace(kind: .bluetooth, identifier: "64:b5:f2:fd:07:a8", label: "Ilia's S23 Ultra")

    func testNoTrustedPlacesIsNeverTrusted() {
        let snapshot = PresenceSnapshot(wifiRouterAddress: "cc:2d:21:5d:f2:e0", connectedBluetoothAddresses: ["64:b5:f2:fd:07:a8"])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: []), [])
    }

    func testMatchingWifiRouterIsTrusted() {
        let snapshot = PresenceSnapshot(wifiRouterAddress: "cc:2d:21:5d:f2:e0", connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [homeWifi, phone]), [homeWifi])
    }

    func testConnectedBluetoothDeviceIsTrustedWithoutWifi() {
        let snapshot = PresenceSnapshot(wifiRouterAddress: nil, connectedBluetoothAddresses: ["64:b5:f2:fd:07:a8"])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [homeWifi, phone]), [phone])
    }

    func testPairedButDisconnectedBluetoothIsNotTrusted() {
        let snapshot = PresenceSnapshot(wifiRouterAddress: nil, connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [phone]), [])
    }

    func testDifferentRouterOnSameKindIsNotTrusted() {
        let snapshot = PresenceSnapshot(wifiRouterAddress: "aa:bb:cc:dd:ee:ff", connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [homeWifi]), [])
    }

    /// A Wi-Fi router and a Bluetooth device could in principle share an address string.
    /// They must never satisfy each other.
    func testKindsDoNotCrossMatch() {
        let wifiWithPhoneAddress = TrustedPlace(kind: .wifi, identifier: "64:b5:f2:fd:07:a8", label: "Impostor")
        let snapshot = PresenceSnapshot(wifiRouterAddress: nil, connectedBluetoothAddresses: ["64:b5:f2:fd:07:a8"])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [wifiWithPhoneAddress]), [])
    }

    // MARK: - Address normalization
    // `arp` prints unpadded octets ("c:2d:...") and IOBluetooth uses dashes and uppercase.
    // All of those must compare equal to the stored form.

    func testNormalizationPadsOctets() {
        XCTAssertEqual(TrustedPresence.normalize("c:2d:21:5:f2:e0"), "0c:2d:21:05:f2:e0")
    }

    func testNormalizationLowercasesAndAcceptsDashes() {
        XCTAssertEqual(TrustedPresence.normalize("64-B5-F2-FD-07-A8"), "64:b5:f2:fd:07:a8")
    }

    func testUnpaddedArpOutputMatchesStoredPlace() {
        let snapshot = PresenceSnapshot(wifiRouterAddress: "cc:2d:21:5d:f2:e0", connectedBluetoothAddresses: [])
        let stored = TrustedPlace(kind: .wifi, identifier: "CC-2D-21-5D-F2-E0", label: "Home")
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [stored]), [stored])
    }

    // MARK: - Settings round-trip

    func testSettingsRoundTripThroughStore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "trusted-presence-tests-\(UUID().uuidString)"))
        let store = TrustedPresenceStore(defaults: defaults)

        XCTAssertEqual(store.load(), TrustedPresenceSettings.disabled)

        var settings = TrustedPresenceSettings.disabled
        settings.keepAwake = true
        settings.disableLockPassword = true
        settings.places = [homeWifi, phone]
        store.save(settings)

        XCTAssertEqual(TrustedPresenceStore(defaults: defaults).load(), settings)
    }

    /// Both switches default to off. A fresh install must never weaken the Mac on its own.
    func testDefaultsAreOff() {
        XCTAssertFalse(TrustedPresenceSettings.disabled.keepAwake)
        XCTAssertFalse(TrustedPresenceSettings.disabled.disableLockPassword)
        XCTAssertTrue(TrustedPresenceSettings.disabled.places.isEmpty)
    }

    // MARK: - What the controller should do with a decision

    func testActionsWhenTrustedAndBothSwitchesOn() {
        var settings = TrustedPresenceSettings.disabled
        settings.keepAwake = true
        settings.disableLockPassword = true
        let plan = TrustedPresence.plan(settings: settings, isTrusted: true)
        XCTAssertTrue(plan.holdAwake)
        XCTAssertFalse(plan.requireLockPassword)
    }

    func testActionsWhenUntrustedRestoreEverything() {
        var settings = TrustedPresenceSettings.disabled
        settings.keepAwake = true
        settings.disableLockPassword = true
        let plan = TrustedPresence.plan(settings: settings, isTrusted: false)
        XCTAssertFalse(plan.holdAwake)
        XCTAssertTrue(plan.requireLockPassword)
    }

    // MARK: - Deciding whether to touch the lock at all
    //
    // Two rules pull against each other:
    //   1. Never leave the Mac unlocked because of something this app did.
    //   2. Never force the password prompt back on if the *user* turned it off themselves
    //      in System Settings. That setting is theirs, not ours.
    // So the app restores the prompt only when it was the one that disabled it.

    func testDisablesOnlyWhenTheFeatureIsOnAndTheStateIsWrong() {
        let trusted = PresencePlan(holdAwake: false, requireLockPassword: false)
        XCTAssertEqual(
            TrustedPresence.lockAction(plan: trusted, featureEnabled: true, currentlyRequiresPassword: true, appDisabledIt: false),
            .disable
        )
        XCTAssertNil(
            TrustedPresence.lockAction(plan: trusted, featureEnabled: false, currentlyRequiresPassword: true, appDisabledIt: false),
            "feature switched off must never disable the prompt"
        )
        XCTAssertNil(
            TrustedPresence.lockAction(plan: trusted, featureEnabled: true, currentlyRequiresPassword: false, appDisabledIt: true),
            "already off - nothing to do"
        )
    }

    func testRestoresWhatTheAppDisabledEvenAfterTheFeatureIsSwitchedOff() {
        let untrusted = PresencePlan(holdAwake: false, requireLockPassword: true)
        XCTAssertEqual(
            TrustedPresence.lockAction(plan: untrusted, featureEnabled: false, currentlyRequiresPassword: false, appDisabledIt: true),
            .restore,
            "turning the feature off must put the password prompt back"
        )
    }

    func testNeverTouchesAPromptTheUserTurnedOffThemselves() {
        let untrusted = PresencePlan(holdAwake: false, requireLockPassword: true)
        XCTAssertNil(
            TrustedPresence.lockAction(plan: untrusted, featureEnabled: true, currentlyRequiresPassword: false, appDisabledIt: false),
            "the app did not disable this - leave the user's own System Settings choice alone"
        )
    }

    func testNothingToDoWhenStateAlreadyMatches() {
        let untrusted = PresencePlan(holdAwake: false, requireLockPassword: true)
        XCTAssertNil(TrustedPresence.lockAction(plan: untrusted, featureEnabled: true, currentlyRequiresPassword: true, appDisabledIt: false))
    }

    // MARK: - Sleep safety
    //
    // The hole this closes: trusted at home, lock password off, lid shut. The Mac sleeps
    // with the prompt already disabled, so anyone who opens it is straight on the desktop.

    func testRelockOnSleepDefaultsOn() {
        XCTAssertTrue(TrustedPresenceSettings.disabled.relockOnSleep)
    }

    func testSleepRestoresThePasswordWhenRelockIsOn() {
        var settings = TrustedPresenceSettings.disabled
        settings.disableLockPassword = true
        XCTAssertTrue(TrustedPresence.planForSleep(settings: settings).requireLockPassword)
    }

    func testSleepLeavesPasswordOffWhenUserTurnedRelockOff() {
        var settings = TrustedPresenceSettings.disabled
        settings.disableLockPassword = true
        settings.relockOnSleep = false
        XCTAssertFalse(TrustedPresence.planForSleep(settings: settings).requireLockPassword)
    }

    /// Sleeping always releases the awake hold — a sleeping Mac is not being held awake.
    func testSleepAlwaysReleasesTheAwakeHold() {
        var settings = TrustedPresenceSettings.disabled
        settings.keepAwake = true
        settings.relockOnSleep = false
        XCTAssertFalse(TrustedPresence.planForSleep(settings: settings).holdAwake)
    }

    /// Quitting the app must never leave the Mac permanently unlocked.
    func testShutdownPlanRestoresEverything() {
        let plan = TrustedPresence.planForShutdown()
        XCTAssertFalse(plan.holdAwake)
        XCTAssertTrue(plan.requireLockPassword)
    }

    /// A switch that is off must leave that behaviour entirely alone, even when trusted.
    func testSwitchedOffFeatureIsNeverApplied() {
        var settings = TrustedPresenceSettings.disabled
        settings.keepAwake = true
        let plan = TrustedPresence.plan(settings: settings, isTrusted: true)
        XCTAssertTrue(plan.holdAwake)
        XCTAssertTrue(plan.requireLockPassword, "lock password must stay required when its switch is off")
    }
}

/// Reading the Bluetooth pairing list is privacy-gated on macOS: without
/// `NSBluetoothAlwaysUsageDescription` the app is terminated, and with it the user gets a
/// permission prompt. Nobody should see that prompt for a feature they are not using.
extension TrustedPresenceTests {
    func testBluetoothIsNotReadWhenNoBluetoothDeviceIsTrusted() {
        XCTAssertFalse(TrustedPresence.needsBluetooth(places: []))
        XCTAssertFalse(TrustedPresence.needsBluetooth(places: [
            TrustedPlace(kind: .wifi, identifier: "cc:2d:21:5d:f2:e0", label: "Home")
        ]))
    }

    func testBluetoothIsReadWhenADeviceIsTrusted() {
        XCTAssertTrue(TrustedPresence.needsBluetooth(places: [
            TrustedPlace(kind: .wifi, identifier: "cc:2d:21:5d:f2:e0", label: "Home"),
            TrustedPlace(kind: .bluetooth, identifier: "64:b5:f2:fd:07:a8", label: "Phone"),
        ]))
    }
}
