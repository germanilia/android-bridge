# Domain Entities — U11 Mac App Shell (SwiftUI)

The Mac shell is an **integration unit**: it owns no protocol entities of its own. Its domain is the
UI/coordination layer that binds Core + plugins + services (U2–U10) to SwiftUI views. Entities below
are app-shell concepts, not wire types.

---

## E1. AppCoordinator (D1)
The top-level orchestrator. Holds references to the shared services and drives the app lifecycle.

| Member | Type | Notes |
|--------|------|-------|
| `start()` | action | Build the dependency graph, restore settings (U10), begin discovery (U3). |
| `showWindow(WindowKind)` | action | Open/focus a feature window. |
| `runOnboarding()` | action | First-run flow: pairing → permissions → one-time BT. |

## E2. WindowKind (enum)
The set of windowed surfaces: `MESSAGES`, `FILES`, `SCREEN`, `CALLS`, `SETTINGS` (+ the menu-bar
status item, always present).

## E3. MenuBarStatus
Derived view of `ConnectionState` (U3) for the menu-bar item: `connected` / `reconnecting` /
`disconnected` (FR-2.3 / US-2.3), plus paired-device name.

## E4. Feature ViewModels (one per surface)
Thin `ObservableObject`s that adapt a feature service to a SwiftUI view. Each holds presentation state
and forwards user intent to its service:

| ViewModel | Binds to service | Surface |
|-----------|------------------|---------|
| `MessagesViewModel` | `MessagingService` (U5) | Messages window |
| `FilesViewModel` | `FileTransferService` (U6) | Files window + drop target |
| `ScreenViewModel` | `ScreenMirrorService` (U8) | Screen window |
| `CallsViewModel` | `CallService` (U9) | Caller-ID popup, history |
| `SettingsViewModel` | `SettingsService` + `PermissionService` (U10) | Settings window |
| `PairingViewModel` | `PairingService` (U2) | Onboarding / devices |
| `StatusViewModel` | `ConnectionService` (U3) | Menu-bar status |

## E5. OnboardingStep (enum)
`PAIRING` → `PERMISSIONS` → `BLUETOOTH_SETUP` → `DONE` (US-1.1, US-9.1, US-8.1). Ordered flow state.

---

## Relationships
```
AppCoordinator ──owns──▶ Services (U2–U10) ──drive──▶ ViewModels ──render──▶ SwiftUI views
ConnectionState (U3) ──▶ MenuBarStatus / StatusViewModel
OnboardingStep ──sequences──▶ PairingViewModel → SettingsViewModel → BT hint
```

## Out of scope for U11 (owned elsewhere)
- All wire/domain entities → U1 + feature units. The shell only presents them.
- Feature business logic → the plugins/services it binds to.
- Android UI → U12.
