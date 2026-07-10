# Frontend Components — U12 Android App Shell (Compose)

Jetpack Compose UI for the Android app. Component tree, per-screen state, interaction + permission
flows, and the service each screen binds to. Pure presentation — logic lives in U2–U10.

> **Selectors**: UI-testable Composables set `Modifier.testTag("…")` + `contentDescription` for
> accessibility (NFR-4.4); pattern `[screen]-[element]-[action]` (e.g. `pairing-scan-button`).

---

## Component tree
```
MainActivity (ComponentActivity)
└── AppTheme (MaterialTheme)
    └── NavHost
        ├── StatusScreen        (StatusViewModel ⟶ ConnectionService U3)
        ├── PairingScreen       (PairingViewModel ⟶ PairingService U2)
        ├── PermissionsScreen   (PermissionsViewModel ⟶ PermissionService U10)
        ├── SettingsScreen      (SettingsViewModel ⟶ SettingsService U10)
        └── OnboardingFlow      (Pairing → Permissions → Bluetooth steps)
LinkForegroundService (hosts the U3 link; ongoing notification)
```
> Current scaffold renders only a single static `HomeScreen` Composable in `MainActivity.kt`
> ("Continuity hub — disconnected"); the screens above are the designed target.

## Screens

### StatusScreen
- **State**: `connectionState`, `pairedDeviceName` (StateFlow).
- **Interactions**: shows connected/reconnecting/disconnected (US-2.3); entry points to other screens.
- **Binds**: `StatusViewModel` → `ConnectionService` (U3).

### PairingScreen
- **State**: `pairedDevices`, scan result.
- **Interactions**: scan the Mac's QR (`consumePairingQr`, U2 / US-1.1); list + unpair (US-1.3).
- **Binds**: `PairingViewModel` → `PairingService` (U2).

### PermissionsScreen
- **State**: per-permission `PermissionStatus` + rationale.
- **Interactions**: request each grant with rationale (US-9.1): notification access, SMS, contacts,
  screen capture, foreground service, Bluetooth; deep-link to system settings when needed.
- **Binds**: `PermissionsViewModel` → `PermissionService` (U10).

### SettingsScreen
- **State**: per-feature `EffectiveFeatureState`, clipboard sync mode, file destination.
- **Interactions**: toggle features (US-9.2); show fix-it hints for blocked features (US-9.3); set
  clipboard mode (U7, default MANUAL) + file destination (U6).
- **Binds**: `SettingsViewModel` → `SettingsService` (U10).

### OnboardingFlow
- **State**: `step: OnboardingStep` (PAIRING → PERMISSIONS → BLUETOOTH_SETUP → DONE).
- **Interactions**: scan QR; grant permissions; guide one-time BT HFP setup (US-8.1).
- **Binds**: `PairingViewModel` (U2) + `PermissionsViewModel` (U10).

## State management
- One `ViewModel` per screen exposing `StateFlow`; Composables collect with
  `collectAsStateWithLifecycle`. State hoisted out of Composables; no logic in UI (BR-9).

## Permission flow
- Uses the Activity Result API for runtime grants and routes special-access grants (notification
  listener, screen capture) through the OS settings, all surfaced via U10 with rationale (US-9.1).

## Validation / errors
- No form validation of its own; surfaces U10 effective state + generic errors (BR-10). A screen for a
  blocked feature shows the fix-it hint and other screens keep working (US-9.3).
