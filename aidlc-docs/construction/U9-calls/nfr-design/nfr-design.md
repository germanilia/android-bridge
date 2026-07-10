# NFR Design — U9 Calls

Concrete patterns realizing the U9 NFRs and the applicable Security Baseline rules. The control plane
rides U1/U3; the audio plane is OS-level Bluetooth HFP and is deliberately out of the protocol.

---

## Privacy & data locality
- **PII never logged**: `LinkLogger` already forbids `number`/`contact` field keys; U9 logs only event
  names + `call.*` type (BR-11, SECURITY-03). Numbers/names live only in `call.*` payloads on the
  encrypted link and in OS-provided UI.
- **Two-plane separation**: control/metadata over mTLS (U3); audio over device-local Bluetooth HFP — no
  call audio ever crosses the LAN/protocol (BR-1, NFR-1.1).

## Security realization (Baseline ON)
| Rule | Realization in U9 | Status |
|------|-------------------|--------|
| SECURITY-01 (in transit) | `call.*` rides the U3 mTLS session | Inherited (U3) |
| SECURITY-05 (input validation) | `call.*` validated against Schema; `call.action` allowlisted `{answer,decline,dial}` (BR-9) | Compliant |
| SECURITY-13 (safe deser) | U1 allowlisted registry; no dynamic deserialization | Inherited (U1) |
| SECURITY-15 (fail-closed) | Unknown action / missing permission → reject or degrade, never blind-actuate | Compliant |
| SECURITY-03 (no-PII logging) | Numbers + contact names never logged (BR-11) | Compliant |
| SECURITY-06 (least privilege) | Requests only phone/InCallService + contacts read; deny-by-default | Compliant |
| SECURITY-01/-12 (at rest) | Cached call history persisted via SecureStore (Keychain/Keystore) | Compliant (if cached) / Deferred |
| SECURITY-10 (supply chain) | Pin deps; scan + SBOM | Deferred (Build & Test) |
| SECURITY-02/-04/-07/-08/-09/-11/-14 | No cloud/web tier; mTLS is the authZ boundary (U3) | N/A |

## Resilience (baseline only — Resiliency extension OFF)
- **Graceful degradation**: no telephony/contacts permission → caller-ID shows number only / feature shown
  unavailable; other features keep working (BR-7/BR-8, NFR-5.2, U10).
- **Allowlisted actuation**: a malformed/unknown `call.action` is dropped, never executed (BR-9, SECURITY-15).

## Performance
- Control messages are tiny JSON envelopes (well under U1's ≤ ~1 ms codec target); perceived call-control
  latency is dominated by link RTT, keeping answer/decline "seamless" (NFR-4.2).

## Testability realization (PBT partial)
- **Kotest** (Kotlin): `Mappers` round-trip incl. `call.history` count/order (PBT-02), number-normalization
  idempotence (PBT-04 advisory), action-allowlist invariant (PBT-03); seeded + shrinking (PBT-07/-08).
- **Environment deviation**: Swift side uses the **dependency-free seeded harness** (this machine has only
  Swift CLT, **no Xcode** → no XCTest/SwiftCheck); PBT-09 intent met; swap to **SwiftCheck + XCTest** with Xcode.
- Telephony/InCallService/contacts/Bluetooth HFP verified by **on-device manual testing**.

## Logical components
`CallStateObserver (InCallService)` → `Mappers` → U3 send; `CallActionHandler` ← U3 (allowlist) →
`InCallService` actuation; `ContactResolver` (perm-gated); `CallHistoryReader` → `call.history`;
audio handled entirely by the OS Bluetooth HFP stack.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
