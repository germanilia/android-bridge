# NFR Design — U4 Notifications

How U4 realizes its NFRs and the applicable Security Baseline / PBT rules. Infrastructure Design is
**skipped** project-wide (local P2P, no cloud).

---

## Security patterns (Baseline ON)
| Rule | Realization in U4 |
|------|-------------------|
| SECURITY-05 (input validation) | `notif.posted` payload Schema (required `pkg/title/text/postedAt`, size caps) checked before render (BR-6); the registry/codec validation is the U1 trust boundary. |
| SECURITY-13 (safe deserialization) | **Inherited** — U1 parses JSON into the typed `Message` via the allowlisted registry; no dynamic deserialization. |
| SECURITY-15 (fail-closed) | **Inherited** — malformed/unknown `notif.posted` dropped + logged by the U3 `MessageRouter`; link stays up (BR-9). U4 adds graceful degradation when listener access is revoked (BR-10). |
| SECURITY-03 (no-PII logging) | `LinkLogger` forbidden-key filter already blocks `title`/`text`/`body`; U4 logs only `pkg`, `msgType`, sizes (BR-8). |
| SECURITY-01 in transit | **Inherited** — every `notif.posted` rides the U3 mTLS session. |
| SECURITY-01/-12 at rest | The `AppAllowlist` persists through `SecureStore` (Keystore/EncryptedSharedPreferences on Android, Keychain on Mac) — never a plaintext file. |
| SECURITY-06 (least privilege) | Requests only notification-listener access; allowlist defaults to **DENY** so nothing mirrors until opted in (BR-3). |
| SECURITY-10 (supply chain) | **Deferred** to Build & Test (pin/scan/SBOM); U4 adds no runtime dep. |
| SECURITY-02/-04/-07/-09/-11/-14 | **N/A** — no cloud/web tier, intermediary, HTTP surface, VPC, or alerting plane. |

## Validation / fail-closed design
- Single inbound path: `ConnectionManager → MessageRouter.route() → NotificationService` — U4 never
  parses raw bytes itself, so the trust boundary stays in U1/U3 (defense in depth, SECURITY-11 spirit).
- Capture path drops denied packages **before** building/sending a message (no leak of disallowed apps).

## Performance / reliability design
- Stateless O(1) mapping + predicate; no caches or back-pressure needed (low-rate control messages).
- Degradation: missing notification-listener grant disables capture only; `PluginRegistry`/U10 surface
  the unavailable state (NFR-5.2).

## PBT design (PARTIAL: PBT-02/-03/-07/-08/-09)
- **PBT-02**: `notif.posted` payload round-trip via Kotest `Arb` generators (and the Swift seeded harness
  on the Mac decode side).
- **PBT-03**: allowlist filter invariant (subset + exact match).
- **PBT-07/-08**: domain generators incl. empty/Unicode strings; Kotest seeds logged, shrinking on;
  Swift harness deterministic by seed (PBT-09 intent met without SwiftCheck — see tech-stack-decisions).

## Environment deviation
Swift CLT only (no Xcode) → Swift PBT runs on the dependency-free seeded harness, not SwiftCheck/XCTest;
identical properties; swap to SwiftCheck + XCTest where Xcode exists.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
