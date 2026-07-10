# NFR Requirements — U8 Screen Mirror (view-only v1)

U8 is a **latency-sensitive streaming feature** over the U3 mTLS session. Its transport guarantees
(encryption, framing, ordering, fail-closed) are inherited from U1/U3; U8 owns capture, encode/decode,
render, and the adaptive-bitrate control loop.

---

## NFR-U8.1 Performance / Latency *(headline NFR)*
- **Target**: end-to-end latency **≤ ~80 ms** on a healthy 5 GHz LAN (NFR-3.1), sustained via adaptive bitrate.
- Per-frame encode + frame + decode work stays well under the **~16 ms/frame @ 60 fps** budget (NFR-U1.2 tie-in).
- AdaptiveBitrateController output bounded `[min, max]` and reacts to link-health within a small window.

## NFR-U8.2 Testability
- Adaptive-bitrate controller is **pure** and property-tested: bounds + monotone direction invariants
  (PBT-03, PBT-07/-08 generators + seeded shrinking).
- `screen.start`/`screen.stop` payloads round-trip (PBT-02, via the U1 codec).
- Capture/encode/decode are hardware codec IO — covered by **on-device manual/integration testing**, not PBT.

## NFR-U8.3 Reliability / correctness
- Stream fault (gap/dup) aborts only that stream and recovers via a fresh keyframe (BR-7, BR-11); the link survives.
- `MediaProjection` consent denial fails closed (no capture) (BR-2).

## NFR-U8.4 Security (Baseline ON — applicable rules)
| Rule | Applies to U8 | How |
|------|---------------|-----|
| SECURITY-01 (encrypt in transit) | Inherited (U3) | Frames ride the mTLS session. |
| SECURITY-05 (input validation) | ✅ | `screen.*` payloads validated against their Schema before use. |
| SECURITY-13 (safe deserialization) | Inherited (U1) | Allowlisted registry; no dynamic deserialization. |
| SECURITY-15 (fail-closed) | ✅ | Consent denial + stream fault → stop/restart, never partial render. |
| SECURITY-03 (no-PII logging) | ✅ | Frame contents never logged (BR-12). |
| SECURITY-06 (least privilege) | ✅ | Only `MediaProjection` screen-capture consent requested; nothing broader. |
| SECURITY-10 (supply chain) | Deferred | Pin codec/runtime deps; scan + SBOM at Build & Test. |
| SECURITY-01/-12 at rest | N/A | U8 persists nothing (no caches). |
| SECURITY-02/-04/-07/-08/-09/-11/-14 | N/A | No cloud/web tier; auth is the mTLS link (U3). |

## NFR-U8.5 Maintainability / portability
- Uses **generic Android** `MediaProjection`/`MediaCodec` only (NFR-6.1, US-10.3) — no Samsung APIs.
- Control-channel seam reserved for US-7.3 so screen control can be added without redesign (NFR-6.2).

## Out of scope for U8 (asserted)
Encryption/framing/ordering (U1/U3), input injection (US-7.3 [Later]), cloud delivery/relay — **N/A**.
