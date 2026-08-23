# Unit / Property Test Instructions — android_bridge

Per the Testing extension (PARTIAL: PBT-02, -03, -07, -08, -09 enforced), the primary test surface is
the **protocol round-trip property tests** plus example tests, in both languages. The Android pure logic
(state machine, chunker, pairing, policy, mappers, mTLS) is unit-tested (24 tests), and the Mac core has
XCTest + SwiftCheck tests.

---

## 1. Kotlin / Kotest (protocol + Android pure logic)
- **Protocol tests:** `cd protocol/kotlin && ./gradlew test`
  - Runs `ProtocolPropertyTest` (PBT-02 control round-trip; PBT-03 self-delimiting framing + frame
    round-trip; domain generators over all `MessageTypes`, PBT-07) and `ProtocolExampleTest`
    (length-prefix, unknown-type/oversize/version-mismatch rejection, END_OF_STREAM) and
    `InteropVectorTest` (shared wire vectors).
  - Framework: JUnit5 + Kotest (`kotest-runner-junit5`, `kotest-property` 5.9.1). Shrinking on by
    default; seed logged on failure (PBT-08).
- **Android module tests:** `cd android && ./gradlew :app:testDebugUnitTest` — **24 JVM unit tests**
  (Kotest, JUnit platform) for the pure Core/feature logic (`ConnectionStateMachine`,
  `StreamChunker`/`StreamReassembler`, `PairingManager`, `ClipboardSyncPolicy`, `PluginRegistry`,
  `Mappers`, `MessageRouter`, `LinkLogger`) plus the in-process **mTLS `TlsIntegrationTest`**.

## 2. Swift (`protocol/swift` + `mac/`) — XCTest + SwiftCheck (primary)
- **Run:** `cd protocol/swift && swift test` (8 tests, 3 SwiftCheck properties × 100 cases) and
  `cd mac && swift test` (10 tests incl. a SwiftCheck stream round-trip property).
- Covers PBT-02 (`decode(encode(m)) == m`), PBT-03 (self-delimiting framing + frame round-trip),
  fail-closed example assertions, and cross-language vector decode.
- **Xcode-free fallback:** `swift run ProtocolCheck` / `swift run MacCheck` — a dependency-free seeded
  `PropertyHarness` (SplitMix64 `PRNG` + `PropertyRunner`) kept for machines without Xcode. It was the
  primary path before Xcode was installed; now `swift test` (SwiftCheck + XCTest) is.

## 3. Meeting Calendar tests

- **Run:** `cd mac && swift test`.
- `MeetingCalendarTests` covers strict overlap boundaries, deterministic candidate order, one-company inference, generic-domain rejection, state/end-time/calendar snapshot persistence, and interrupted-finalization recovery.
- SwiftCheck property `PBT-03: calendar matches always overlap and ignore input order` runs 100 cases using the shrinkable `CalendarIntervals` domain generator.
- Current Mac result: 30 XCTest cases pass, including both SwiftCheck properties at 100 cases each.

## 4. PBT compliance (Partial mode)
| Rule | Where satisfied |
|------|-----------------|
| PBT-02 round-trip | Kotlin `ProtocolPropertyTest`, Swift `ProtocolPropertyTests` (SwiftCheck) |
| PBT-03 invariant/framing | both suites (self-delimiting framing, frame round-trip, stream chunk/reassemble) |
| PBT-07 generators | domain generators over registry types + frame headers + byte payloads |
| PBT-08 shrinking + seed | Kotest auto-shrink + seed log; SwiftCheck shrinking + seeded runs |
| PBT-09 framework | Kotlin = Kotest Property Testing; Swift = **SwiftCheck** (harness kept as fallback) |

## What is verified vs. not
- **Verified:** U1 codec property + example tests pass in both languages; cross-language interop passes;
  24 Android unit tests (incl. in-process mTLS handshake + pinned-peer rejection); Mac core XCTest+SwiftCheck.
- **Not unit-tested here:** device/hardware-bound behavior (telephony, screen capture, Bluetooth HFP,
  NSD discovery, live two-device mTLS link) — integration/manual on real hardware, not unit-testable.

## 5. Clipboard and Second Brain reliability tests

- `cd android && ./gradlew :app:testDebugUnitTest --no-daemon`: 46 tests passed.
- `ClipboardSyncTest` includes generated mode/user-action inputs and verifies `AUTO || userInitiated`.
- `cd mac && swift test`: 33 XCTest passed plus two 100-case SwiftCheck properties.
- `SecondBrainStoreRefreshTests` verifies live configured-root changes and Markdown-tree revision changes.
- Full protocol tests remain green in Kotlin and Swift, including control-message round trips and oversize rejection.

## 6. Meeting customer automation tests

- `cd mac && swift test`: 40 XCTest passed.
- `MeetingCustomerAutomationTests` covers catalog seeding/deduplication, learned match persistence, ambiguity, correction/forget, and old calendar snapshot decoding.
- SwiftCheck PBT-02 generates customer/event/domain scenarios and verifies learned association JSON round trips across 100 cases.
- SwiftCheck PBT-03 generates event intervals and verifies padded matching invariants and input-order independence across 100 cases.
- `MeetingCalendarTests` pins 15-minute boundary tolerance and strongest-overlap ordering.

## 7. Direct distribution updater tests

- `python3 -m unittest scripts/test_release.py`: version, names, manifest, aliases, checksums, SBOM shape, and workflow policy.
- `cd mac && swift test`: strict stable metadata, semantic comparison, bounded DMG integrity, owned-path cleanup, and rejection tests in `MacUpdateTests`.
- `cd android && ./gradlew :app:testDebugUnitTest --no-daemon`: strict stable metadata, version-code comparison, bounded APK integrity, cancellation/cleanup, and malformed-input tests in `AndroidUpdateTest`.
- Platform compile checks prove the native Mac controller and Android PackageManager/FileProvider adapters integrate with existing apps.
