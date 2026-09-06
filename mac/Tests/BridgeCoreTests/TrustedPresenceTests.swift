import XCTest
@testable import BridgeCore

/// Trusted Presence decides whether the Mac is somewhere the user has marked safe.
/// The decision must be pure and total: same inputs, same answer, no I/O.
final class TrustedPresenceTests: XCTestCase {

    private let homeWifi = TrustedPlace(kind: .wifi, identifier: "fox5", label: "fox5")
    private let phone = TrustedPlace(kind: .bluetooth, identifier: "64:b5:f2:fd:07:a8", label: "Ilia's S23 Ultra")

    func testNoTrustedPlacesIsNeverTrusted() {
        let snapshot = PresenceSnapshot(wifiSSID: "fox5", connectedBluetoothAddresses: ["64:b5:f2:fd:07:a8"])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: []), [])
    }

    func testMatchingWifiRouterIsTrusted() {
        let snapshot = PresenceSnapshot(wifiSSID: "fox5", connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [homeWifi, phone]), [homeWifi])
    }

    func testConnectedBluetoothDeviceIsTrustedWithoutWifi() {
        let snapshot = PresenceSnapshot(wifiSSID: nil, connectedBluetoothAddresses: ["64:b5:f2:fd:07:a8"])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [homeWifi, phone]), [phone])
    }

    func testPairedButDisconnectedBluetoothIsNotTrusted() {
        let snapshot = PresenceSnapshot(wifiSSID: nil, connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [phone]), [])
    }

    func testDifferentNetworkOnSameKindIsNotTrusted() {
        let snapshot = PresenceSnapshot(wifiSSID: "Company-Guest", connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [homeWifi]), [])
    }

    /// A Wi-Fi router and a Bluetooth device could in principle share an address string.
    /// They must never satisfy each other.
    func testKindsDoNotCrossMatch() {
        let wifiNamedLikeTheAddress = TrustedPlace(kind: .wifi, identifier: "64:b5:f2:fd:07:a8", label: "Impostor")
        let snapshot = PresenceSnapshot(wifiSSID: nil, connectedBluetoothAddresses: ["64:b5:f2:fd:07:a8"])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [wifiNamedLikeTheAddress]), [])
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

    /// IOBluetooth reports dashes and uppercase; stored places may hold either form.
    func testBluetoothAddressFormatsCompareEqual() {
        let snapshot = PresenceSnapshot(wifiSSID: nil, connectedBluetoothAddresses: ["64-B5-F2-FD-07-A8"])
        let stored = TrustedPlace(kind: .bluetooth, identifier: "64:b5:f2:fd:07:a8", label: "Phone")
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [stored]), [stored])
    }

    /// Network names are names, not addresses: they are matched exactly, never normalized.
    /// "Sela" and "sela" are two different networks as far as macOS is concerned.
    func testNetworkNamesAreCaseSensitive() {
        let snapshot = PresenceSnapshot(wifiSSID: "sela", connectedBluetoothAddresses: [])
        let wrongCase = TrustedPlace(kind: .wifi, identifier: "Sela", label: "Sela")
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [wrongCase]), [])
    }

    /// A name with punctuation that looks like an address must not be mangled by normalization.
    func testNetworkNameWithAddressLikeCharactersIsNotNormalized() {
        let snapshot = PresenceSnapshot(wifiSSID: "AP-5:2", connectedBluetoothAddresses: [])
        let stored = TrustedPlace(kind: .wifi, identifier: "AP-5:2", label: "AP-5:2")
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: [stored]), [stored])
    }

    /// Several networks can be trusted at once, without ever visiting them.
    func testManyNetworksCanBeTrustedAndOnlyThePresentOneMatches() {
        let places = ["fox5", "fox-mesh", "sela", "Running_Fox"].map {
            TrustedPlace(kind: .wifi, identifier: $0, label: $0)
        }
        let snapshot = PresenceSnapshot(wifiSSID: "sela", connectedBluetoothAddresses: [])
        XCTAssertEqual(TrustedPresence.present(in: snapshot, trusted: places).map(\.identifier), ["sela"])
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
            TrustedPlace(kind: .wifi, identifier: "fox5", label: "fox5")
        ]))
    }

    func testBluetoothIsReadWhenADeviceIsTrusted() {
        XCTAssertTrue(TrustedPresence.needsBluetooth(places: [
            TrustedPlace(kind: .wifi, identifier: "fox5", label: "fox5"),
            TrustedPlace(kind: .bluetooth, identifier: "64:b5:f2:fd:07:a8", label: "Phone"),
        ]))
    }
}

/// Wi-Fi places used to store the router's MAC address; they now store the network name.
/// Settings saved by the older build must not silently stop matching.
extension TrustedPresenceTests {
    func testOldRouterAddressEntryIsMigratedToItsNetworkName() {
        let old = TrustedPlace(kind: .wifi, identifier: "d4:35:1d:4f:c1:8d", label: "fox5")
        XCTAssertEqual(
            TrustedPresence.migrate(places: [old]),
            [TrustedPlace(kind: .wifi, identifier: "fox5", label: "fox5")]
        )
    }

    /// An auto-generated label carries no network name, so there is nothing to migrate to.
    /// Dropping it is correct: a place that can never match must not sit in the list
    /// looking as though it protects something.
    func testOldEntryWithNoUsableNameIsDropped() {
        let old = TrustedPlace(kind: .wifi, identifier: "d4:35:1d:4f:c1:8d", label: "Wi-Fi c1:8d")
        XCTAssertEqual(TrustedPresence.migrate(places: [old]), [])
    }

    func testBluetoothPlacesAreLeftAloneByMigration() {
        let device = TrustedPlace(kind: .bluetooth, identifier: "68:d9:3c:77:71:7e", label: "Ilia's Mouse")
        XCTAssertEqual(TrustedPresence.migrate(places: [device]), [device])
    }

    func testAlreadyMigratedNetworksAreUntouched() {
        let current = TrustedPlace(kind: .wifi, identifier: "fox5", label: "fox5")
        XCTAssertEqual(TrustedPresence.migrate(places: [current]), [current])
    }

    /// A network genuinely named like an address would be destroyed by a naive rule,
    /// so migration only rewrites when the label offers a different, non-address name.
    func testNetworkNamedLikeAnAddressSurvivesWhenLabelMatchesIt() {
        let odd = TrustedPlace(kind: .wifi, identifier: "d4:35:1d:4f:c1:8d", label: "d4:35:1d:4f:c1:8d")
        XCTAssertEqual(TrustedPresence.migrate(places: [odd]), [])
    }
}
