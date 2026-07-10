# NFR Design — U10 Settings & Permissions

Concrete patterns realizing the U10 NFRs and the applicable Baseline Security rules. Single
consolidated design (patterns + logical components). Infrastructure Design is **skipped** (local
control plane, no cloud).

---

## Logical components
- **PluginRegistry (B6, pure)** — in-memory toggle set, seeded from the persisted snapshot. Source of
  truth for "did the user enable this".
- **PermissionService (S6)** — platform adapter that requests and queries OS permissions; the only
  IO-bearing piece. Re-queries on resume (BR-6).
- **EffectiveStateResolver (pure function, L4)** — `(toggles, permissionStatuses) → EffectiveFeatureState`.
  Platform-agnostic; the security-critical decision lives here (separation of concerns, SECURITY-11).
- **SettingsStore** — `SettingsService` over `SecureStore` (B5) for encrypted persistence.

## Security pattern realization (cite rule IDs)
- **Least privilege — SECURITY-06**: `FeatureRequirements` declares the *minimal* permission set per
  feature; `requestPermission` only ever asks for those. `effectiveState` enforces "active iff toggle
  on AND all required granted" — a feature can never run with a broader grant or a missing one (BR-4/-7).
- **Fail-closed degradation — SECURITY-15**: `EffectiveStateResolver` defaults any
  unknown/denied/revoked permission to inactive; the blocked plugin stops emitting/handling. Isolation
  guarantees siblings are unaffected (BR-9/-10).
- **Encryption at rest — SECURITY-01/-12**: `SettingsSnapshot` persists only through `SecureStore`
  (Keychain on Mac; `AndroidSecureStore` = Keystore-derived `MasterKey` + EncryptedSharedPreferences).
  No plaintext settings file (BR-12).
- **No-PII logging — SECURITY-03**: routed through `LinkLogger` (forbidden-key filter); only
  FeatureId/PermissionId + result (BR-13).
- **Generic errors — SECURITY-09**: permission failures render as user-facing fix-it hints; no stack
  traces / internal paths.
- **Safe-deser / validation — SECURITY-05/-13 (Inherited)**: U10 consumes no untrusted wire input;
  inbound validation is owned by U1 codec + U3 `MessageRouter`.
- **Supply chain — SECURITY-10 (Deferred)**: pinning + scan + SBOM at Build & Test.
- **N/A**: SECURITY-02/-04/-07/-08/-11(rate-limit)/-14 — no cloud/web tier, network intermediary,
  server-side authz, public endpoint, or cloud alerting in a local control plane.

## Reliability / degradation pattern
- Effective state is **recomputed on every toggle change and on app resume** (state may drift if the
  user revokes a permission in System Settings). The resolver is pure → recomputation is cheap and
  deterministic (NFR-U10.2).
- Partial-failure isolation: a feature's blocked state is local to that `FeatureId`; the registry and
  resolver never throw across features.

## Performance pattern
- All operations are O(features) over a fixed small set; no perf budget required. Permission queries
  are the only latency source and are user-initiated.

## Testability pattern (PBT Partial)
- **PBT-03 (invariant/oracle)**: property test asserts `effectiveState == enabled && allGranted`
  against a reference truth-table across all toggle×permission combinations.
- **PBT-02 (round-trip)**: `decode(encode(snapshot)) == snapshot`.
- **PBT-09 framework**: Kotlin → Kotest property testing. Swift → the repo's dependency-free seeded
  harness (`PropertyHarness.swift` + `ProtocolCheck`) because **this machine has only Swift CLT (no
  Xcode)** → XCTest/SwiftCheck unavailable; intent (generators + shrinking-lite + seeded repro) is met;
  swap to SwiftCheck + XCTest on a machine with Xcode.
- Example tests pin each feature's degradation hint and a persist→restart→restore round-trip.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
