# Code Summary — U1 Protocol / Transport core

**Status: DONE and tested in both languages.** U1 is the one unit whose Code Generation has fully
run; it is the foundation every other unit depends on. The wire contract is implemented twice (Swift
+ Kotlin), kept in lockstep with the canonical spec, and proven equivalent by shared cross-language
vectors.

---

## What the code does
Turns domain objects ⇄ bytes and guards the inbound trust boundary:
- **Control codec** — length-prefixed (4-byte BE) UTF-8 JSON envelope `{id,type,protocolVersion,replyTo,payload}`, 1 MiB cap, oversize rejected pre-parse (BR-1/-2).
- **Frame codec** — fixed 13-byte BE header `streamId·sequence·length·flags` + payload, 64 KiB default chunk, `END_OF_STREAM` flag (BR-3/-4).
- **Type registry + validation** — allowlisted `MessageTypes`; `validate()` enforces version, known type, non-empty id (SECURITY-05/-13); typed failures (`ProtocolError`/`ProtocolException`) carry no payload (BR-18).
- **Fail-closed semantics** — malformed → typed error for caller to drop+log; version mismatch → typed error U3 uses to reject the link (BR-7/-14/-15).

## Real files
| Area | Path |
|------|------|
| Spec (canonical) | `protocol/PROTOCOL.md` |
| Kotlin model | `protocol/kotlin/src/main/kotlin/com/androidbridge/protocol/Model.kt` |
| Kotlin codec | `protocol/kotlin/src/main/kotlin/com/androidbridge/protocol/Codec.kt` |
| Kotlin PBT + examples | `protocol/kotlin/src/test/kotlin/com/androidbridge/protocol/ProtocolPropertyTest.kt` |
| Kotlin interop test | `protocol/kotlin/src/test/kotlin/com/androidbridge/protocol/InteropVectorTest.kt` |
| Swift model | `protocol/swift/Sources/DeviceLinkProtocol/Model.swift` |
| Swift codec | `protocol/swift/Sources/DeviceLinkProtocol/Codec.swift` |
| Swift PBT harness | `protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift` |
| Swift check runner | `protocol/swift/Sources/ProtocolCheck/main.swift` |
| Shared wire vectors | `protocol/vectors/control-messages.jsonl` |

## Test status (verified)
- **Kotlin (Kotest):** PBT-02 control round-trip, PBT-03 self-delimiting framing + frame round-trip, plus example tests for length prefix, unknown-type/oversize/version-mismatch rejection, END_OF_STREAM. Domain generators over all registry types (PBT-07), shrinking + seed logging (PBT-08).
- **Swift (`ProtocolCheck`):** same PBT-02/-03 properties via the dependency-free seeded harness (500 cases each) + the same fail-closed example assertions. Prints `ALL PROTOCOL CHECKS PASSED` / exits non-zero on failure.
- **Cross-language interop:** both suites decode the identical `protocol/vectors/control-messages.jsonl` vectors, proving the two impls accept the same on-the-wire JSON.

## Environment note
The Swift property tests run via the **dependency-free seeded harness** (`PropertyHarness.swift` +
`swift run ProtocolCheck`) because this machine has only the Swift **Command Line Tools** (no Xcode),
so **XCTest/SwiftCheck are unavailable**. The harness meets PBT-09's intent (generators + seeded
reproducibility + minimal-failure reporting). On a machine with Xcode, swap to SwiftCheck + XCTest
with no change to the properties. The Kotlin side uses Kotest Property Testing as planned.

## Not in U1 (owned elsewhere)
mTLS/connection/streams lifecycle → U3; per-feature payload *semantics* → each feature unit. U1 fixes
only the envelope, framing, registry, validation, and codecs.
