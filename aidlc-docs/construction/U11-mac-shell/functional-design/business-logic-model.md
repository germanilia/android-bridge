# Business Logic Model — U11 Mac App Shell (SwiftUI)

Coordination flows for the macOS app. The shell holds **no business logic of its own** — it wires the
Core/plugins/services (U2–U10) into SwiftUI surfaces and sequences onboarding. All transforms and
rules live in the units it integrates.

---

## L1. App launch  `AppCoordinator.start()`
1. Build the dependency graph: Core (Pairing, Connection, Router, SecureStore, Discovery, Logger) +
   the seven plugins + their services + view-models.
2. Restore settings via `SettingsService` (U10) — seed feature toggles.
3. If no paired device → `runOnboarding()`; else begin discovery via `DiscoveryService` (U3).
4. Install the menu-bar status item bound to `StatusViewModel`.

## L2. Onboarding  `runOnboarding()`  (US-1.1 / US-9.1 / US-8.1)
Ordered `OnboardingStep` flow:
1. **PAIRING** — `PairingViewModel` shows the QR / scan flow → `PairingService.consumePairingQr`.
2. **PERMISSIONS** — `SettingsViewModel` requests macOS permissions (notifications, Local Network,
   Bluetooth) with rationale (U10).
3. **BLUETOOTH_SETUP** — guide the one-time HFP pairing for call audio (U9 / US-8.1); confirm ready.
4. **DONE** — proceed to steady state.

## L3. Surface a feature window  `showWindow(kind)`
Open/focus the SwiftUI scene for `kind`; its view-model subscribes to the relevant service's published
state (inbound messages, transfer progress, screen frames, call events).

## L4. Reflect connection state
`StatusViewModel` observes `ConnectionService.observeState()` (U3) and maps `ConnectionState` →
menu-bar icon + label (connected/reconnecting/disconnected, FR-2.3). Always visible (US-2.3).

## L5. Render inbound events (representative)
- `notif.posted` → macOS native notification (via `NotificationService` U4).
- `sms.received` / `sms.thread` → `MessagesViewModel` (U5).
- file/screen streams → `FilesViewModel` / `ScreenViewModel` (U6/U8).
- `call.incoming` → caller-ID popup via `CallsViewModel` (U9).

Each path is: service publishes → view-model updates `@Published` state → SwiftUI re-renders. The shell
adds no validation/transformation (that happened in U1/U3 and the plugins).

---

## Data flow (inbound SMS, representative)
```
peer ─(U3 mTLS)─▶ MessageRouter ─▶ MessagingService(U5) ─publishes─▶ MessagesViewModel ─▶ SwiftUI list
```

## Testable Properties (PBT-01)
**No PBT properties identified.** Rationale: U11 is pure UI/integration/orchestration — it sequences
onboarding and binds services to SwiftUI views. It performs no data transformation, serialization,
or algorithmic computation; those properties are owned by the units it integrates (U1 codec round-trips,
U6 chunk/reassemble, U10 effective-state, etc.). View-models and onboarding are validated by
**example-based + UI tests**, not property-based tests (PBT-10 division of labor).
