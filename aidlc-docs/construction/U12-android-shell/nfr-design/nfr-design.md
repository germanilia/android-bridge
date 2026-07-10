# NFR Design — U12 Android App Shell (Compose)

Concrete patterns realizing the U12 NFRs and applicable Baseline Security rules. Single consolidated
design. Infrastructure Design is **skipped** (local mobile app, no cloud).

---

## Logical components
- **MainActivity + NavHost** — Compose host and navigation graph across Status/Pairing/Permissions/
  Settings (+ feature surfaces).
- **AppContainer (manual DI)** — singletons for Core + plugins + services, shared with the service.
- **LinkForegroundService** — always-on host for the U3 link with an ongoing notification.
- **ViewModels** — one per screen, projecting service state to `StateFlow`.

## Background-liveness pattern (NFR-U12.1)
- **Foreground service + START_STICKY**: `LinkForegroundService` calls `startForeground` with the
  `link_status` ongoing notification; holds the shared `ConnectionService` from `AppContainer` so
  discovery + mTLS persist while the UI is gone (FR-2.2 / US-2.2).
- **Single graph**: services are constructed once in `AppContainer` and shared — no request-scoped
  singletons, no duplicate Core instances (BR-4).

## Responsiveness pattern (NFR-U12.2)
- `StateFlow` + `collectAsStateWithLifecycle`; bulk streams (U6/U8) on background coroutines; the UI
  thread only renders state/decoded frames.

## Reliability pattern (NFR-U12.3)
- **Degradation surfacing**: screens read U10 `EffectiveFeatureState`; a blocked feature renders
  unavailable + fix-it hint, isolated from other screens (US-9.3).
- **Connection state**: Status screen shows reconnecting during transient drops (U3 owns retry).

## Security pattern realization (cite rule IDs)
- **Least privilege — SECURITY-06 (Compliant)**: the manifest declares only the permissions the enabled
  features need; runtime/special-access grants are requested through U10 (rationale-first). *(Current
  scaffold manifest is minimal and must be extended with these declarations — see code-summary.)*
- **No-PII logging — SECURITY-03 (Compliant)**: shell logging via `LinkLogger` (forbidden-key filter);
  UI/lifecycle only (BR-11).
- **Generic errors — SECURITY-09 (Compliant)**: one error-presentation path → generic messages +
  fix-it hints; no stack traces (BR-10).
- **Encryption in transit — SECURITY-01 (Inherited)**: all data crosses the U3 mTLS link.
- **Encryption at rest — SECURITY-01/-12 (Inherited)**: settings/trust persist via `AndroidSecureStore`
  (Keystore + EncryptedSharedPreferences) — U2/U10.
- **Validation / safe-deser / fail-closed — SECURITY-05/-13/-15 (Inherited)**: U1 codec + U3 router.
- **Supply chain — SECURITY-10 (Deferred)**: version catalog + lockfile + scan + SBOM at Build & Test.
- **N/A**: SECURITY-02/-04/-07/-08/-11/-14 — no cloud/web tier, network intermediary, server authz,
  public endpoint, rate limiting, or cloud alerting in a mobile shell.

## Accessibility pattern (NFR-4.4)
- Interactive Composables set `testTag` + `contentDescription`; TalkBack support; Material touch targets.

## Testability pattern
- **No PBT properties (PBT-01)** — UI/integration/DI; properties live in U1–U10.
- Example + instrumented UI tests (Compose UI test, `testTag` selectors) cover navigation, status
  mapping, permission flow, and degradation rendering. These need an **emulator/device + Android SDK**,
  not run in this environment (see tech-stack-decisions).
