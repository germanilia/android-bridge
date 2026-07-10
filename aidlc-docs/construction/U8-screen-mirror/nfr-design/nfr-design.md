# NFR Design — U8 Screen Mirror (view-only v1)

Concrete patterns realizing the U8 NFRs and the applicable Security Baseline rules. Transport-level
controls are inherited from U1/U3; U8 adds capture/encode/decode and the adaptive control loop.

---

## Performance & latency
- **Adaptive control loop**: `AdaptiveBitrateController.adjust(signal)` runs on a short cadence, clamping
  `current` to `[min, max]` and steering toward `targetLatencyMs` (NFR-3.1, BR-8/BR-9). Pure + deterministic.
- **Hardware codecs**: `MediaCodec` encode + `VideoToolbox` decode keep per-frame work under the
  ~16 ms/frame @ 60 fps budget (BR-10, NFR-U1.2 tie-in).
- **Binary streams, not base64**: encoded access-units go over U1 binary frames (BR-6), avoiding JSON/base64
  overhead on the hot path.

## Resilience (baseline only — Resiliency extension OFF)
- **Stream-scoped fail-closed**: a `sequence` gap/dup faults only that screen `streamId`; renderer waits
  for a fresh keyframe and re-issues `screen.start` (BR-7, BR-11). The link + other streams survive.
- **Consent fail-closed**: `MediaProjection` denial aborts start; no silent capture (BR-2, SECURITY-15).

## Security realization (Baseline ON)
| Rule | Realization in U8 | Status |
|------|-------------------|--------|
| SECURITY-01 (in transit) | Frames ride the U3 mTLS session | Inherited (U3) |
| SECURITY-05 (input validation) | `screen.start`/`screen.stop` validated against Schema before acting | Compliant |
| SECURITY-13 (safe deser) | U1 allowlisted registry; no dynamic deserialization | Inherited (U1) |
| SECURITY-15 (fail-closed) | Consent denial + stream fault → stop/restart, never partial render | Compliant |
| SECURITY-03 (no-PII logging) | `LinkLogger`; frame contents never logged (BR-12) | Compliant |
| SECURITY-06 (least privilege) | Only `MediaProjection` consent requested; CaptureIndicator shown | Compliant |
| SECURITY-10 (supply chain) | Pin codec/runtime deps; scan + SBOM | Deferred (Build & Test) |
| SECURITY-01/-12 (at rest) | U8 persists nothing | N/A |
| SECURITY-02/-04/-07/-08/-09/-11/-14 | No cloud/web tier; mTLS is the authZ boundary (U3) | N/A |

## Testability realization (PBT partial)
- **AdaptiveBitrateController** invariants via **Kotest** (Kotlin); bounds + monotone-direction (PBT-03,
  PBT-07/-08 generators + seeded shrinking).
- `screen.*` round-trip via the U1 codec (PBT-02).
- **Environment deviation**: Swift side runs the **dependency-free seeded harness** (`swift run ProtocolCheck`
  style) because this machine has **only Swift CLT (no Xcode)** → no XCTest/SwiftCheck; PBT-09 intent met;
  swap to **SwiftCheck + XCTest** on a machine with Xcode.
- Latency/codec performance verified by **on-device measurement**, not CI gate.

## Logical components
`MediaProjectionSource` → `MediaCodecEncoder` → `FrameSink (U1 FrameCodec)` → U3 stream →
`FrameSource` → `VideoToolboxDecoder` → `MirrorView (U11)`; `AdaptiveBitrateController` observes link health.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
