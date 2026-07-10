# Services — android_bridge

Services orchestrate the Core components and feature plugins within each app. Each app (Mac, Android) has the same service set, implemented natively. Services hold orchestration/coordination logic; plugins hold feature behavior; Core holds transport/trust.

---

## S1. DiscoveryService
- **Responsibility**: Drive `DeviceDiscovery` — advertise this device, browse for the paired peer, and hand a found endpoint to `ConnectionService`.
- **Orchestrates**: `DeviceDiscovery` (B1) → `ConnectionService`.
- **Triggers**: app start, network change.

## S2. PairingService
- **Responsibility**: Coordinate first-time trust: generate identity, present/scan QR, pin peer, persist to `SecureStore`; expose paired-device list + unpair.
- **Orchestrates**: `PairingManager` (B2) + `SecureStore` (B5).
- **Stories**: US-1.1–1.3.

## S3. ConnectionService
- **Responsibility**: Lifecycle of the secure link — connect on discovery, maintain heartbeat, auto-reconnect, expose connection state to the UI, and provide `send`/`openStream` to feature services.
- **Orchestrates**: `ConnectionManager` (B3) + `MessageRouter` (B4).
- **Stories**: US-2.1–2.4.

## S4. MessageRouter (service-facing facade over B4)
- **Responsibility**: Register each feature plugin against its message types; validate + dispatch inbound messages; enforce fail-closed drop of malformed input.
- **Orchestrates**: `MessageRouter` (B4) ↔ all feature plugins.
- **Cross-cutting**: CC-VALID, SECURITY-05/-13/-15.

## S5. Feature Services (one per plugin)
Thin services that connect a plugin to the UI/view-models and to `ConnectionService`:
- **NotificationService** → C1 (US-3.x)
- **MessagingService** → C2 (US-4.x, read-only v1)
- **FileTransferService** → C3 (US-5.x)
- **ClipboardService** → C4 (US-6.x)
- **ScreenMirrorService** → C5 (US-7.x, view-only v1)
- **CallService** → C6 (US-8.x) — also coordinates the one-time Bluetooth onboarding hint (audio path is OS-level HFP)
- **SettingsService** → C7 (US-9.x) — feature toggles, permission status, drives graceful degradation

## S6. PermissionService
- **Responsibility**: Centralize OS-permission requests/status per platform; feed `SettingsService` and gate feature activation (US-9.1, US-9.3).
- **Orchestrates**: platform permission APIs + `SettingsPermissions` (C7).

---

## Orchestration Flows (representative)

### Pairing (US-1.1)
`UI → PairingService.createPairingQR()/consumePairingQR()` → `PairingManager` pins peer → `SecureStore` persists → `ConnectionService.connect()`.

### Steady-state inbound message (e.g., SMS received, US-4.1)
Peer → `ConnectionManager` (mTLS) → `MessageRouter.route()` (validate) → `MessagingService` → UI/view-model renders.

### Outbound action (e.g., answer call, US-8.3)
`UI → CallService.sendAction(answer)` → `ConnectionService.send(call.action)` → peer `CallPlugin.answer()` → phone answers; audio via Bluetooth HFP.

### Bulk stream (e.g., file send, US-5.1 / screen, US-7.1)
`FileTransferService/ScreenMirrorService → ConnectionService.openStream()` → `FrameCodec` frames over the mTLS session → peer reassembles → write/render.

---

## Service → Component Map
| Service | Core deps | Plugin | Stories |
|---|---|---|---|
| DiscoveryService | DeviceDiscovery, ConnectionManager | — | US-2.1 |
| PairingService | PairingManager, SecureStore | — | US-1.x |
| ConnectionService | ConnectionManager, MessageRouter | — | US-2.x |
| MessageRouter (facade) | MessageRouter | all | cross-cutting |
| NotificationService | ConnectionService | C1 | US-3.x |
| MessagingService | ConnectionService | C2 | US-4.x |
| FileTransferService | ConnectionService (streams) | C3 | US-5.x |
| ClipboardService | ConnectionService | C4 | US-6.x |
| ScreenMirrorService | ConnectionService (streams) | C5 | US-7.x |
| CallService | ConnectionService | C6 | US-8.x |
| SettingsService | PluginRegistry | C7 | US-9.x |
| PermissionService | — (platform APIs) | C7 | US-9.1/9.3 |
