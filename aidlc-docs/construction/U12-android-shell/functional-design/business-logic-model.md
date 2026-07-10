# Business Logic Model — U12 Android App Shell (Compose)

Coordination flows for the Android app. The shell holds **no business logic of its own** — it hosts the
link via a foreground service, wires Core/plugins/services (U2–U10) through manual DI, and renders
Compose screens. All transforms and rules live in the integrated units.

---

## L1. App start
1. `Application`/`MainActivity` builds the `AppContainer` (Core + plugins + services), using
   `AndroidSecureStore` for persistence.
2. Restore settings via `SettingsService` (U10) — seed feature toggles.
3. Start `LinkForegroundService` so the link survives backgrounding (FR-2.2 / US-2.2).
4. If no paired device → onboarding; else `DiscoveryService` (U3) begins.

## L2. Foreground service lifecycle  `LinkForegroundService`
1. `onCreate` creates the `link_status` notification channel.
2. `onStartCommand` → `startForeground(notification)` (ongoing, IMPORTANCE_LOW); returns `START_STICKY`
   so the OS restarts it (US-2.2).
3. Holds the `ConnectionService`/`ConnectionManager` so discovery + mTLS continue while the UI is gone.

## L3. Onboarding  (US-1.1 / US-9.1 / US-8.1)
Ordered `OnboardingStep`: PAIRING (`PairingService.consumePairingQr` via QR scan) → PERMISSIONS
(request Android grants with rationale, U10) → BLUETOOTH_SETUP (guide one-time HFP, U9) → DONE.

## L4. Render screens
Each `ViewModel` exposes a `StateFlow` collected by its Composable; user intent is forwarded to the
bound service. The shell performs no validation/transformation (done in U1/U3 + plugins).

## L5. Reflect connection state
`StatusViewModel` collects `ConnectionService.observeState()` (U3) → Status screen shows
connected/reconnecting/disconnected (FR-2.3 / US-2.3).

---

## Data flow (status, representative)
```
ConnectionManager(U3) ─state─▶ ConnectionService ─StateFlow─▶ StatusViewModel ─▶ Compose Status screen
LinkForegroundService ──keeps the above alive while backgrounded──
```

## Testable Properties (PBT-01)
**No PBT properties identified.** Rationale: U12 is UI/integration/DI plus the foreground-service host —
it performs no data transformation, serialization, or algorithmic computation. Those properties belong
to the units it integrates (U1 codec round-trips, U6 chunk/reassemble, U7 sync-policy, U10
effective-state, etc.). Compose screens and the service lifecycle are validated by **example-based +
instrumented UI tests**, not property-based tests (PBT-10 division of labor). The foreground service is
IO/OS-bound and not a PBT target.
