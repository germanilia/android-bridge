# Domain Entities — U12 Android App Shell (Compose)

The Android shell is an **integration unit**: it owns no protocol entities. Its domain is the
Compose UI + the always-on `LinkForegroundService` that hosts the link, plus DI wiring of Core +
plugins + services (U2–U10). Entities below are app-shell concepts, not wire types.

---

## E1. LinkForegroundService (D2)
The always-on host that keeps the device link alive while the app is backgrounded (FR-2.2). Mirrors the
real scaffold `android/LinkForegroundService.kt`.

| Member | Type | Notes |
|--------|------|-------|
| `onStartCommand(...)` | lifecycle | `startForeground` with an ongoing status notification; `START_STICKY`. |
| ongoing notification | Notification | Channel `link_status`, `IMPORTANCE_LOW`, ongoing (US-2.2). |
| foreground type | `connectedDevice` | Declared in the manifest. |

## E2. Screen (Compose destination enum)
The navigable screens: `STATUS`, `PAIRING`, `PERMISSIONS`, `SETTINGS` (+ per-feature surfaces:
`MESSAGES`, `FILES`, `SCREEN`, `CALLS` as applicable on the phone side).

## E3. ViewModels (one per screen)
`androidx.lifecycle.ViewModel`s exposing UI state (`StateFlow`) and forwarding intent to services:

| ViewModel | Binds to | Screen |
|-----------|----------|--------|
| `StatusViewModel` | `ConnectionService` (U3) | Status |
| `PairingViewModel` | `PairingService` (U2) | Pairing / devices |
| `PermissionsViewModel` | `PermissionService` (U10) | Permissions |
| `SettingsViewModel` | `SettingsService` (U10) | Settings |

## E4. AppContainer (manual DI)
Holds singletons: Core (Pairing, Connection, Router, `SecureStore`=`AndroidSecureStore`, Discovery,
Logger), the seven plugins, and the feature services. Constructed at `Application`/Activity start and
shared with the foreground service.

## E5. OnboardingStep (enum)
`PAIRING` → `PERMISSIONS` → `BLUETOOTH_SETUP` → `DONE` (mirrors the Mac flow; US-1.1, US-9.1, US-8.1).

---

## Relationships
```
Application ──builds──▶ AppContainer ──provides──▶ Services (U2–U10) ──drive──▶ ViewModels ──▶ Compose
AppContainer ──hosts──▶ LinkForegroundService (keeps U3 link alive)
ConnectionState (U3) ──▶ StatusViewModel ──▶ Status screen
```

## Out of scope for U12 (owned elsewhere)
- All wire/domain entities → U1 + feature units; the shell only presents them.
- Feature business logic → the plugins/services it binds to.
- Mac UI → U11.
