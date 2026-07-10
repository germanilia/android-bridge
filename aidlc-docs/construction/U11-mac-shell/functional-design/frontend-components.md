# Frontend Components — U11 Mac App Shell (SwiftUI)

Menu-bar-first macOS UI built with SwiftUI. Component hierarchy, per-view state, interaction flows,
and the service each surface binds to. Pure presentation — logic lives in U2–U10.

> **Selectors**: `data-testid` is a web concept and is **N/A** in SwiftUI. UI-testable controls expose
> **accessibility identifiers** (`.accessibilityIdentifier("…")`) + labels; pattern
> `[surface]-[element]-[action]` (e.g. `pairing-scan-button`). Keyboard nav + VoiceOver per NFR-4.4.

---

## Component hierarchy
```
AppCoordinator (App entry)
├── MenuBarExtra  ── StatusView            (StatusViewModel ⟶ ConnectionService U3)
├── Window: Messages   ── MessagesView     (MessagesViewModel ⟶ MessagingService U5)
├── Window: Files      ── FilesView        (FilesViewModel ⟶ FileTransferService U6)
├── Window: Screen     ── ScreenView       (ScreenViewModel ⟶ ScreenMirrorService U8)
├── Window: Calls      ── CallsView + CallerIDPopup (CallsViewModel ⟶ CallService U9)
├── Window: Settings   ── SettingsView     (SettingsViewModel ⟶ SettingsService/PermissionService U10)
└── OnboardingFlow     ── Pairing/Permissions/Bluetooth steps (PairingViewModel U2, SettingsViewModel U10)
```

## Surfaces

### StatusView (menu-bar)
- **State**: `connectionState`, `pairedDeviceName`.
- **Interactions**: click → menu (open windows, unpair, quit). Always visible (BR-5).
- **Binds**: `StatusViewModel` → `ConnectionService.observeState()`.

### MessagesView
- **State**: `threads: [SmsThread]`, `selectedThread`, `messages`.
- **Interactions**: select thread → load history (U5). Read-only in v1 (no compose box; US-4.3 Later —
  layout leaves room for a future reply field).
- **Binds**: `MessagingService` (U5).

### FilesView
- **State**: `transfers: [TransferProgress]`, `destination`.
- **Interactions**: **drag-and-drop** files onto the window/drop zone → `offerFile`/`sendFile` (US-5.1);
  per-transfer progress + result; set destination (US-5.3).
- **Binds**: `FileTransferService` (U6).

### ScreenView
- **State**: `isMirroring`, decoded frame surface, `latencyMs`.
- **Interactions**: start/stop mirroring (US-7.2); view-only (no input injection — US-7.3 Later).
- **Binds**: `ScreenMirrorService` (U8).

### CallsView + CallerIDPopup
- **State**: `incomingCall?`, `history: [CallRecord]`.
- **Interactions**: incoming → popup with name/number/photo (US-8.2); Answer/Decline (US-8.3); dial /
  pick contact (US-8.4); browse history (US-8.5). Audio is HFP (OS-level), never in-app.
- **Binds**: `CallService` (U9).

### SettingsView
- **State**: per-feature `EffectiveFeatureState`, permission statuses.
- **Interactions**: toggle features (US-9.2); launch permission prompts with rationale (US-9.1); show
  fix-it hints for blocked features (US-9.3).
- **Binds**: `SettingsService` + `PermissionService` (U10).

### OnboardingFlow
- **State**: `step: OnboardingStep` (PAIRING → PERMISSIONS → BLUETOOTH_SETUP → DONE).
- **Interactions**: show pairing QR / scan; request permissions; guided one-time BT setup (US-8.1).
- **Binds**: `PairingViewModel` (U2) + `SettingsViewModel` (U10).

## State management
- One `ObservableObject` view-model per surface; services publish via Combine/`@Published`; views are
  thin `@StateObject`/`@ObservedObject` consumers. No business logic in views (BR-6).

## Validation / errors
- No form validation logic of its own; surfaces U10 effective-state and generic error messages (BR-8).
- A surface is enabled only when its feature is `ACTIVE` (U10), else shows the fix-it hint.
