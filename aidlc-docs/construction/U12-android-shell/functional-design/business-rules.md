# Business Rules — U12 Android App Shell (Compose)

Coordination and presentation rules for the Android app. IDs (BR-x) referenced by NFR Design and Code
Generation. The shell defers all data rules to the integrated units.

---

## Foreground service & link liveness (FR-2.2 / US-2.2)
- **BR-1**: A **foreground service** (`LinkForegroundService`) hosts the link so continuity works while
  the app is backgrounded; it shows an **ongoing** status notification (channel `link_status`).
- **BR-2**: The service returns `START_STICKY` so the OS restarts it after being killed; it holds the
  `ConnectionService` instance (shared via the `AppContainer`, not a request-scoped singleton).
- **BR-3**: The foreground-service type is `connectedDevice` and the service is declared in the manifest
  (currently a known gap — see code-summary).

## Lifecycle & DI
- **BR-4**: `AppContainer` is built once at app start and shared between the UI and the foreground
  service — one Core/plugin/service graph, no duplicate instances.
- **BR-5**: Settings are restored (U10) before feature surfaces are shown; with no paired device,
  onboarding runs first (US-2.1).

## Onboarding order (US-1.1 / US-9.1 / US-8.1)
- **BR-6**: Onboarding follows pairing → permissions → one-time Bluetooth HFP → done; a later step is
  not offered until the prior completes.

## Permissions & status
- **BR-7**: Permission requests are routed through U10 (rationale-first, least privilege); a screen for a
  blocked feature shows the U10 fix-it hint (US-9.3).
- **BR-8**: The Status screen always reflects the live `ConnectionState` (FR-2.3 / US-2.3).

## Presentation / separation of concerns
- **BR-9**: Composables + view-models hold only UI state and forward intent; **no business logic,
  validation, or wire encoding** in the shell (it's all in U1–U10).

## Errors, privacy, accessibility
- **BR-10 (SECURITY-09)**: User-facing errors are **generic** — no stack traces/internal detail.
- **BR-11 (CC-PRIV / SECURITY-03)**: The shell logs only UI/lifecycle events via `LinkLogger` — never
  bodies/numbers/contacts/tokens.
- **BR-12 (NFR-4.4)**: Interactive elements carry Compose **testTags** + content descriptions; standard
  Android accessibility support.

## Portability (NFR-6.1 / US-10.3)
- **BR-13**: Uses **generic Android public APIs only** (no DeX/Flow/Knox); targets Android 13+.

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-10.1 (build/run Android app) | whole unit + README (Build & Test) |
| US-2.2 / FR-2.2 (background link) | BR-1, BR-2, BR-3 |
| US-2.3 / FR-2.3 (status visible) | BR-8 |
| US-1.1, US-9.1, US-8.1 (onboarding) | BR-6 |
| US-9.3 (degradation surfacing) | BR-7 |
| US-10.3 / NFR-6.1 (generic Android) | BR-13 |
| SECURITY-09 / CC-PRIV / NFR-4.4 | BR-10, BR-11, BR-12 |
