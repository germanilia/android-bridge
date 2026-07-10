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

## 3. PBT compliance (Partial mode)
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
