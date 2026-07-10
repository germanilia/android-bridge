# NFR Requirements — U1 Protocol / Transport core

U1 is a **pure, deterministic library** (bytes ⇄ domain objects + validation). It has no network,
storage, or UI, so service-oriented NFRs (availability, scaling, rate limiting) live in U3, not here.

---

## NFR-U1.1 Testability *(headline NFR)*
- Round-trip property tests in **both** languages: `decode(encode(m)) == m` (PBT-02) and
  `decodeFrame(encodeFrame(h,p)) == (h,p)` + self-delimiting framing (PBT-03).
- Domain generators across all registry `MessageType`s (PBT-07); shrinking + seed-logged CI (PBT-08).
- Example-based tests pin known-good and known-bad vectors per `MessageType` (PBT-10 complement).

## NFR-U1.2 Performance
- **Target** (measured, not CI-gated): control `encode`/`decode` ≤ ~1 ms; 64 KiB frame
  `encodeFrame`/`decodeFrame` ≤ ~2 ms on M1 Mac / modern Android phone (Q3).
- Rationale: keeps the codec far under the ~16 ms/frame budget at 60 fps screen mirroring (U8).
- Oversize declared lengths are rejected **before** allocation/parse (BR-2) — bounds worst-case work.

## NFR-U1.3 Reliability / correctness
- Codecs are **total**: every input yields a valid typed object or a typed `ProtocolError` (BR-13).
- Deterministic + side-effect-free → trivially reproducible; no flakiness surface.
- Fail-closed on malformed input (BR-14/-16/-17); never throws an uncaught exception across the boundary.

## NFR-U1.4 Security (Baseline ON — applicable rules)
| Rule | Applies to U1 | How |
|------|---------------|-----|
| SECURITY-05 (input validation) | ✅ | Total validation of every inbound message/frame (BR-10..-13). |
| SECURITY-13 (safe deserialization) | ✅ | JSON parsed into typed objects via allowlisted registry; no dynamic/unsafe deserialization. |
| SECURITY-15 (fail-closed) | ✅ | Drop+log, abort stream, reject on version mismatch (BR-14..-17). |
| SECURITY-03 (no-PII logging) | ✅ | Codec/security logs carry only `type`,`id`,`streamId`,sizes,reason — never payloads (BR-18). |
| SECURITY-10 (supply chain) | ✅ | Pin SwiftCheck/Kotest exact versions; scanning + SBOM at Build & Test (Q4). |
| SECURITY-01/-02/-04/-06/-07/-08/-09/-11/-12/-14 | N/A | No storage, network intermediary, web headers, IAM, auth, or alerting in a pure codec lib. |

## NFR-U1.5 Maintainability / portability
- `protocol/PROTOCOL.md` is the canonical spec; Swift + Kotlin impls must stay in lockstep with it (US-10.2).
- Codec code has zero dependency on app/UI/transport layers (clean separation, NFR-6.2).
- Public API surface is small and identical in shape across both languages (encode/decode/encodeFrame/decodeFrame/validate).

## Out of scope for U1 (asserted)
Availability, horizontal scaling, throughput-under-load, rate limiting, DR/failover — **N/A** (no
running service). Connection resilience/auto-reconnect = **U3**.
