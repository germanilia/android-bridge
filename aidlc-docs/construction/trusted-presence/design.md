# Increment 6 — Trusted Presence (Mac)

**Goal.** Let the user nominate Wi-Fi networks and Bluetooth devices that mean "I am
somewhere safe", and relax the Mac's locking while one of them is present.

Two independent behaviours, both off by default:

| Switch | What it does | Secret needed |
|---|---|---|
| Keep the Mac awake | Holds an `NSProcessInfo` activity so the display never idles, so the Mac never reaches the lock screen. Lid-close still sleeps and still locks. | none |
| Turn off the wake password | Runs `sysadminctl -screenLock off` / `immediate`. Screen still sleeps and locks; waking does not prompt. | the user's macOS login password |

## Why a router MAC address, not a network name

`networksetup -getairportnetwork en0` reports `You are not associated with an AirPort
network` on macOS 26, and `ipconfig getsummary en0` returns the literal string `<redacted>`
for both `SSID` and `BSSID`. CoreWLAN's `ssid()`/`bssid()` return `nil` without Location
authorization. Verified on macOS 26.5.1 (build 25F80).

So a Wi-Fi place is identified by the **MAC address of its router**: `ipconfig getsummary en0`
gives `Router : <ip>`, and `arp -n <ip>` gives its hardware address. This needs no permission
at all, and identifies the same physical access point that a BSSID would.

Consequence: a mesh network gives each access point a different address. The UI therefore
offers "trust the network I am on right now" rather than a list, so a user can add each node.

Deliberately **not** added: `NSLocationWhenInUseUsageDescription`. The network name would be
cosmetic only (the user already labels each entry), and `mac/scripts/make-macos-app.sh`
documents that TCC grants are bound to the signing identity — not worth risking the app's
existing Calendar/Microphone/ScreenCapture grants for a label.

**Required and added: `NSBluetoothAlwaysUsageDescription`.** Reading the paired-device list
IS privacy-gated inside a bundled app. Without the key macOS terminates the process with no
crash report:

> This app has crashed because it attempted to access privacy-sensitive data without a usage
> description. The app's Info.plist must contain an NSBluetoothAlwaysUsageDescription key…

A bare command-line binary reads the same list with no key and no prompt, so a CLI probe does
**not** prove a bundled app is safe. Verified only by launching the signed `.app` via `open`.

Because the key alone still means a permission prompt, `PresenceSensor.snapshot(includeBluetooth:)`
reads Bluetooth only when a trusted Bluetooth device exists, and the tab lists paired devices
behind an explicit "Show paired Bluetooth devices" button. A Wi-Fi-only user is never prompted.

## Files

| File | Role |
|---|---|
| `mac/Sources/BridgeCore/TrustedPresence.swift` | Pure model + decisions. No I/O, fully tested. |
| `mac/Sources/BridgeCore/PresenceSensor.swift` | Reads router MAC (`ipconfig`+`arp`) and IOBluetooth connection state. |
| `mac/Sources/BridgeCore/ScreenLockControl.swift` | Awake hold, `sysadminctl` wrapper, `LoginPasswordStore` (login Keychain). |
| `mac/Sources/BridgeCore/TrustedPresenceController.swift` | `ObservableObject`: 20s poll, sleep/wake observers, applies plans. |
| `mac/Sources/BridgeApp/TrustedPresenceTab.swift` | The tab (`.tag(4)`). |
| `mac/Tests/BridgeCoreTests/TrustedPresenceTests.swift` | 25 tests over the pure logic. |

Edited: `BridgeApp.swift` (tab), `main.swift` (tray item ⌘T, `presence.start()`,
`presence.stop()` on terminate), `MacCheck/main.swift` (hardware smoke output).

## Safety rules, and the tests that hold them

1. **Defaults are off.** A fresh install never weakens the Mac. — `testDefaultsAreOff`
2. **A switch that is off is never applied.** — `testSwitchedOffFeatureIsNeverApplied`
3. **Kinds never cross-match.** A Bluetooth address can never satisfy a Wi-Fi entry even if
   the strings are equal. — `testKindsDoNotCrossMatch`
4. **Bluetooth counts only while connected**, not merely paired. — `testPairedButDisconnectedBluetoothIsNotTrusted`
5. **Sleep restores the password** by default (`relockOnSleep`, default true). Without it a
   Mac that slept at home opens with no password anywhere else. — `testSleepRestoresThePasswordWhenRelockIsOn`
6. **Quitting the app restores locking.** — `testShutdownPlanRestoresEverything`, `presence.stop()`
7. **The app restores only what the app disabled.** It never forces the prompt back on if the
   user disabled it themselves in System Settings, and it never strands the Mac unlocked when
   the feature is switched off. Tracked in `trustedPresence.appDisabledLockPassword`, persisted
   so a crash still recovers. — `testRestoresWhatTheAppDisabledEvenAfterTheFeatureIsSwitchedOff`,
   `testNeverTouchesAPromptTheUserTurnedOffThemselves`
8. **A Wi-Fi-only user never triggers a Bluetooth prompt.** — `testBluetoothIsNotReadWhenNoBluetoothDeviceIsTrusted`
9. **The login password goes to `sysadminctl` on stdin** (`-password -`), never in `argv`, so it
   does not appear in `ps` output.

## Honest limitations

- A router MAC or Bluetooth address can be copied by someone who knows yours. This is
  convenience, not authentication. The UI says so in both section footers.
- With `relockOnSleep` on (the default), lid-close still asks for a password once on wake.
  Turning it off removes that, and the UI marks the text orange to say why that is worse.
- Up to a 20-second window after leaving a trusted network before the password is restored.

## Verification

| Check | Command | Result |
|---|---|---|
| Mac tests | `swift test` | 125 passed, 0 failed |
| Trusted Presence tests | `swift test --filter TrustedPresenceTests` | 25 passed |
| Xcode-free smoke | `swift run MacCheck` | 14 checks passed; reads real router MAC + 16 paired devices |
| App bundle | `mac/scripts/make-macos-app.sh` | builds, signs, installs |
| Bundled app survives launch | `open -a /Applications/AndroidBridge.app` | alive past 60s (was: terminated in <8s before the plist key) |

## Follow-up fixes found by running the bundled app (2026-09-06)

Three bugs that only appear in the signed `.app`, never in `swift run` or a CLI probe:

1. **Startup termination.** Reading the paired-device list without
   `NSBluetoothAlwaysUsageDescription` makes macOS kill the process — no crash report, nothing
   in `~/Library/Logs/DiagnosticReports`. Only `log stream --predicate 'process == "AndroidBridge"'`
   during an `open` shows the reason. Fixed by adding the key; see the section above.

2. **Menu bar icon pinned into a reserved zone.** `NSStatusItem Preferred Position` is distance
   in points from the right edge, so smaller is further right. Measured on this Mac: Clock 66,
   Control Center 153–386, every third-party item 519–923. The app asked for **100**, inside the
   range macOS reserves for itself, so the request was not honoured and the icon landed far left
   where it is hidden first. Now **400** — immediately left of the system cluster, the rightmost
   slot a third-party item can actually hold. Migrated under a new `pinnedRight.v2` key.

3. **One-shot overflow check misfired.** The Dock-icon fallback ran once, 6 s after launch, and
   caught the menu bar mid-layout:

   ```
   [..288] menu bar icon hidden=true      # the old one-shot check fired here
   [..289] menu bar icon hidden=false     # one second later it was actually visible
   ```

   So the app permanently showed a Dock icon and a "Menu bar is full" warning while its menu bar
   icon was fine. Replaced with a 30 s repeating `checkMenuBarVisibility(announce:)` that moves
   between `.regular` and `.accessory` as the icon appears and disappears, and warns only on the
   first transition into hidden.

**Lesson for this increment:** a CLI probe cannot validate TCC behaviour or menu bar layout.
Verify by launching the signed bundle with `open` and watching `log stream` plus
`/tmp/androidbridge-diag.txt`.

## Change: Wi-Fi matched by network name, not router address (2026-09-06)

The router-MAC design had a usability wall the user hit immediately: a network can only be
learned while connected to it, so "trust this network" could only ever offer the one you were
on, and there was no way to add a second. The request was a picker like the Bluetooth one.

A picker of names requires matching by name, and reading the current network's name requires
Location authorization — the thing the original design avoided. The user chose the picker
after being shown the trade-off.

**What changed**

| Before | After |
|---|---|
| `.wifi` identifier = router MAC from `ipconfig` + `arp` | `.wifi` identifier = network name (SSID) from CoreWLAN |
| No permission | `NSLocationWhenInUseUsageDescription` + `CLLocationManager` authorization |
| Add only the network you are on | Pick any of the ~116 networks this Mac remembers, via `networksetup -listpreferredwirelessnetworks en0` (needs no permission) |
| One entry per mesh access point | One entry covers a whole mesh |
| Spoofable only by copying a MAC | Spoofable by broadcasting the name |

`TrustedPresence.comparable(kind:_:)` now decides comparison per kind: Bluetooth addresses are
normalized, network names are compared exactly. Names are case-sensitive and may contain `:`
or `-`, so running them through MAC normalization would corrupt them —
`testNetworkNameWithAddressLikeCharactersIsNotNormalized` holds that line.

**Migration.** Settings written by the previous build hold a router MAC in a `.wifi` entry and
would silently never match again. `TrustedPresence.migrate(places:)` rewrites such an entry to
the label the user gave it (the real case on this Mac: identifier `d4:35:1d:4f:c1:8d`, label
`fox5` → identifier `fox5`), and drops entries whose label carries no name — an empty label,
another address, or the old auto-generated `"Wi-Fi <last 5 of address>"`. Dropping beats
keeping: a place that can never match must not sit in the list looking as though it works.
The upgrade is written back on first load so stored settings match what is in use.

**Picker usability.** This Mac remembers 116 networks, so the list is searchable above 8
entries and ordered: the network you are on, then trusted ones, then the rest alphabetically.

**If Location is denied** the Wi-Fi section says so and offers a button to System Settings.
No Wi-Fi entry can match, so the Mac simply stays locked — failing closed, which is correct.

## UI and window fixes (2026-09-06)

**1. Long lists get their own scroll area.** 116 remembered networks in a `Form` made the tab
scroll forever. Both pickers are now a `ScrollView` + `LazyVStack` at a fixed height (Wi-Fi 260,
Bluetooth 220) with a search field over the Wi-Fi list and an "N trusted of M" count under each,
so the page stays one readable length no matter how many networks or devices the Mac knows.

**2. The dashboard opened in its own Space and could not be dragged to another desktop.**
Two causes, both fixed in `main.swift`:

- The window never set `collectionBehavior`. An `.accessory` app's window is treated as
  transient, so macOS parks it in a Space of its own. Now
  `[.managed, .participatesInCycle, .fullScreenPrimary]` — an ordinary window that belongs to a
  Space like any other.
- `checkMenuBarVisibility` called `NSApp.setActivationPolicy` whenever the menu bar icon
  appeared or disappeared, including while the dashboard was open. Changing activation policy
  re-parents every open window and can strand one. `applyActivationPolicy()` now defers while
  a window is visible and runs on `windowWillClose` instead. Nothing is lost: the Dock icon
  exists to reach the app when no window is showing, which is exactly when it may now change.

The one-shot check also moved from 6s to 20s — the 6s reading was demonstrably a false
"hidden" (`hidden=true` at ..288, `hidden=false` at ..289) and cost a needless policy flip.
