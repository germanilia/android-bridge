# Business Rules — U11 Mac App Shell (SwiftUI)

Coordination and presentation rules for the macOS app. IDs (BR-x) referenced by NFR Design and Code
Generation. The shell defers all data rules to the integrated units.

---

## Lifecycle & coordination
- **BR-1**: `AppCoordinator.start()` builds the full dependency graph and restores persisted settings
  (U10) **before** any feature surface is shown.
- **BR-2**: On launch with **no paired device**, onboarding runs first; with a paired device, discovery
  + connection (U3) begin automatically (US-2.1).

## Onboarding order (US-1.1 / US-9.1 / US-8.1)
- **BR-3**: Onboarding follows the fixed order pairing → permissions → one-time Bluetooth HFP setup →
  done. A later step is not offered until the prior completes.
- **BR-4**: The Bluetooth step is **guided and one-time** (US-8.1); after confirmation, call audio
  "just works" via HFP and the app never streams call audio (P2/FR-8.4).

## Status visibility (FR-2.3 / US-2.3)
- **BR-5**: The menu-bar status item is always present and reflects the live `ConnectionState`
  (connected / reconnecting / disconnected) plus the paired-device name.

## Presentation / separation of concerns
- **BR-6**: View-models hold only presentation state and forward intent to services; **no business
  logic, validation, or wire encoding** lives in the shell (it's all in U1–U10).
- **BR-7**: A feature window/surface is shown as available only when its feature is `ACTIVE` per U10's
  effective state; otherwise it shows the U10 fix-it hint (US-9.3).

## Errors & privacy
- **BR-8 (SECURITY-09)**: User-facing errors are **generic** (no stack traces, internal paths, or
  framework details); failures route to a friendly message + fix-it hint.
- **BR-9 (CC-PRIV / SECURITY-03)**: The shell logs only UI/lifecycle events via the platform logger —
  never message bodies, numbers, contacts, or tokens.

## Accessibility (NFR-4.4)
- **BR-10**: Interactive controls expose **accessibility identifiers + labels**; the app supports
  keyboard navigation and VoiceOver. (Note: `data-testid` is a web concept and is **N/A** for SwiftUI —
  accessibility identifiers are used for UI-test selection instead.)

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-10.1 (build/run Mac app) | whole unit + README (Build & Test) |
| US-2.3 / FR-2.3 (status visible) | BR-5 |
| US-1.1, US-9.1, US-8.1 (onboarding) | BR-3, BR-4 |
| US-9.3 (degradation surfacing) | BR-7 |
| SECURITY-09 (generic errors) | BR-8 |
| CC-PRIV / SECURITY-03 | BR-9 |
| NFR-4.4 (accessibility) | BR-10 |
