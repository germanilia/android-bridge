# NFR Design — U11 Mac App Shell (SwiftUI)

Concrete patterns realizing the U11 NFRs and applicable Baseline Security rules. Single consolidated
design. Infrastructure Design is **skipped** (local desktop app, no cloud).

---

## Logical components
- **AppCoordinator** — composition root: builds Core + plugins + services + view-models; owns the
  app lifecycle and onboarding sequence.
- **MenuBarExtra + StatusView** — always-present status surface bound to `ConnectionState` (U3).
- **Feature windows + view-models** — one MVVM pair per surface (Messages/Files/Screen/Calls/Settings),
  each bound to its feature service.
- **OnboardingFlow** — ordered step machine (pairing → permissions → BT).

## UX / responsiveness pattern (NFR-U11.1/.3)
- **MVVM + Combine**: services publish state; view-models project it to `@Published`; SwiftUI re-renders.
- **Main-actor UI, background bulk**: file/screen streams (U6/U8) run off the main actor; the shell only
  renders decoded frames, staying within the U8 latency budget (NFR-3.1).
- **Menu-bar-first**: lightweight always-on status; windows lazy-open on demand.

## Reliability pattern (NFR-U11.4)
- **Degradation surfacing**: each surface reads U10 `EffectiveFeatureState`; a blocked feature renders
  unavailable + fix-it hint, isolated from siblings (US-9.3 / SECURITY-15-by-inheritance).
- **Connection state**: menu bar shows reconnecting during transient drops (U3 owns retry); UI never
  blocks awaiting the link.

## Security pattern realization (cite rule IDs)
- **Encryption in transit — SECURITY-01 (Inherited)**: the shell never opens a socket; all data crosses
  the U3 mTLS link.
- **No-PII logging — SECURITY-03 (Compliant)**: shell logging is UI/lifecycle only; the platform logger
  receives no bodies/numbers/contacts (BR-9).
- **Generic errors — SECURITY-09 (Compliant)**: a single error-presentation path renders generic
  messages + fix-it hints; no stack traces or internal paths reach the user (BR-8).
- **Validation / safe-deser / fail-closed — SECURITY-05/-13/-15 (Inherited)**: owned by U1 codec + U3
  router; the shell renders already-validated, already-routed data.
- **Encryption at rest — SECURITY-01/-12 (Inherited)**: trust material + settings persist via U2/U10
  Keychain-backed SecureStore, not the shell.
- **Supply chain — SECURITY-10 (Deferred)**: `Package.resolved` pinning + scan + SBOM at Build & Test.
- **N/A**: SECURITY-02/-04/-06(server)/-07/-08/-11/-14 — no cloud/web tier, network intermediary,
  server authz, public endpoint, rate limiting, or cloud alerting in a desktop shell.

## Accessibility pattern (NFR-4.4)
- Every interactive control sets an accessibility identifier + label; full keyboard navigation +
  VoiceOver. (`data-testid` is N/A in SwiftUI; UI tests select via accessibility identifiers.)

## Testability pattern
- **No PBT properties (PBT-01)** — the shell is UI/integration; properties live in U1–U10.
- UI/example tests cover onboarding ordering, status mapping, drag-and-drop intent, and degradation
  rendering. These require **Xcode** (XCUITest) — unavailable on this machine (Swift CLT only), so they
  are authored for a machine with Xcode (see tech-stack-decisions environment deviation).
