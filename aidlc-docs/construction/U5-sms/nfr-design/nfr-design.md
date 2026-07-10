# NFR Design — U5 SMS / MMS

How U5 realizes its NFRs and the applicable Security Baseline / PBT rules. Infrastructure Design is
**skipped** project-wide (local P2P, no cloud).

---

## Security patterns (Baseline ON)
| Rule | Realization in U5 |
|------|-------------------|
| SECURITY-05 (input validation) | `sms.received`/`sms.thread` payload Schemas (required fields, size caps) checked before render (BR-7); registry/codec validation is the U1 trust boundary. |
| SECURITY-13 (safe deserialization) | **Inherited** — U1 parses into typed `Message` via the allowlisted registry; no dynamic deserialization. |
| SECURITY-15 (fail-closed) | **Inherited** — malformed `sms.*` dropped + logged by U3 router; link stays up (BR-7). U5 adds graceful degradation on missing SMS/contacts perms (BR-9). |
| SECURITY-03 (no-PII logging) | `body`, sender `address`, contact names never logged; `LinkLogger` forbidden-key filter + U5 logging only `msgType`/`threadId`/sizes (BR-5). |
| SECURITY-01 in transit | **Inherited** — all `sms.*` ride the U3 mTLS session. |
| SECURITY-01/-12 at rest | Cached thread history persisted via `SecureStore` (Keystore/Keychain), never plaintext. |
| SECURITY-06 (least privilege) | Requests only SMS read (mandatory) + contacts read (optional); deny-by-default per feature toggle (U10). |
| SECURITY-10 (supply chain) | **Deferred** to Build & Test; U5 adds no runtime dep. |
| SECURITY-02/-04/-07/-09/-11/-14 | **N/A** — no cloud/web tier, intermediary, HTTP surface, VPC, or alerting plane. |

## Validation / fail-closed design
- Single inbound path `ConnectionManager → MessageRouter.route() → MessagingService`; U5 never parses
  raw bytes — trust boundary stays in U1/U3 (defense in depth).
- Contact resolution failure degrades to raw address, never blocks rendering (BR-9).

## Performance / reliability design
- Stateless O(1) mapping; grouping O(n log n) per thread — fine for realistic histories. MMS bytes ride
  U6 frame streams, keeping control messages small.
- Degradation: SMS perm revoked → feature unavailable via `PluginRegistry`/U10 (NFR-5.2).

## PBT design (PARTIAL: PBT-02/-03/-07/-08/-09)
- **PBT-02**: `sms.received`/`sms.thread` payload round-trip via Kotest `Arb` generators (+ Swift seeded
  harness on the decode side).
- **PBT-03**: `ConversationGrouping` invariant — count preserved, single-thread membership, per-thread
  `receivedAt` ordering.
- **PBT-07/-08**: generators include empty/Unicode bodies + multi-thread message lists; Kotest seeds
  logged + shrinking on; Swift harness deterministic by seed (PBT-09 intent met — see tech-stack-decisions).

## Environment deviation
Swift CLT only (no Xcode) → Swift PBT runs on the dependency-free seeded harness, not SwiftCheck/XCTest;
identical properties; swap to SwiftCheck + XCTest where Xcode exists.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
