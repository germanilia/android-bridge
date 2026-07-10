# Components — android_bridge

High-level component identification. Detailed business logic is deferred to per-unit Functional Design.

**Architecture style**: feature-plugin modules on a shared **Core** (connection, pairing, discovery, routing, secure storage), present on **both** the Mac and Android apps; a **shared Device-Link Protocol** defines the contract. Call audio is carried by **Bluetooth HFP** at the OS level and is therefore *not* a protocol message — only call *control/metadata* flows over the link.

---

## A. Shared Device-Link Protocol (contract, mirrored in both codebases)

### A1. Message Envelope
- **Purpose**: Common wrapper for all control messages.
- **Responsibilities**: Define `{ id, type, protocolVersion, payload }`; length-prefixed JSON encoding/decoding; stable type registry.
- **Interface**: `encode(Message) -> bytes`, `decode(bytes) -> Message`. (Round-trip is a PBT target — PBT-02.)

### A2. Binary Frame
- **Purpose**: Framing for bulk/streaming data (file chunks, screen frames).
- **Responsibilities**: Small header `{ streamId, sequence, length, flags }` + payload bytes; ordering and end-of-stream markers.
- **Interface**: `encodeFrame(header, bytes) -> bytes`, `decodeFrame(bytes) -> (header, bytes)`.

### A3. Message Type Registry
- **Purpose**: Single source of truth for message types per feature.
- **Responsibilities**: Enumerate types (e.g., `pair.request`, `notif.posted`, `sms.received`, `file.offer`, `clip.update`, `screen.start`, `call.incoming`, `call.action`); map type → payload schema.
- **Interface**: `schemaFor(type) -> Schema`; validation hooks (SECURITY-05/-13).

---

## B. Core (shared responsibilities, implemented natively per platform)

### B1. DeviceDiscovery
- **Purpose**: Find the paired peer on the LAN.
- **Responsibilities**: Advertise this device + browse for peers via **mDNS/Bonjour** (`NWBrowser`/`NWListener` on macOS, `NsdManager` on Android); surface discovered endpoints.
- **Interface**: `startAdvertising()`, `startBrowsing()`, `onPeerFound(endpoint)`, `stop()`.

### B2. PairingManager
- **Purpose**: Establish and revoke trust.
- **Responsibilities**: Generate a per-device TLS keypair/cert; QR encode/scan of pairing material; **pin** the peer cert (trust-on-first-use); manage the trusted-device list.
- **Interface**: `generateIdentity()`, `createPairingQR() -> QRPayload`, `consumePairingQR(QRPayload)`, `pinPeer(cert)`, `listPaired()`, `unpair(deviceId)`.

### B3. ConnectionManager
- **Purpose**: Own the secure link.
- **Responsibilities**: Establish **mutual TLS** against pinned certs; reject unpinned peers (CC-SEC); multiplex control messages + binary streams; heartbeat; **auto-reconnect** (FR-2.4); expose connection state.
- **Interface**: `connect(endpoint)`, `send(Message)`, `openStream(streamId) -> Stream`, `onMessage(handler)`, `state: ConnectionState`, `disconnect()`.

### B4. MessageRouter
- **Purpose**: Dispatch inbound messages to the right plugin.
- **Responsibilities**: Validate + safely deserialize inbound messages (CC-VALID); route by `type` to the registered plugin; drop malformed messages (fail-closed, SECURITY-15).
- **Interface**: `register(type, plugin)`, `route(Message)`, `unregister(type)`.

### B5. SecureStore
- **Purpose**: Encrypted persistence for sensitive data.
- **Responsibilities**: Store keys/certs and sensitive caches in **Keychain** (macOS) / **Keystore + EncryptedSharedPreferences** (Android) (SECURITY-01/-12).
- **Interface**: `put(key, value)`, `get(key)`, `delete(key)`.

### B6. PluginRegistry
- **Purpose**: Wire features into the core.
- **Responsibilities**: Register/enable/disable feature plugins; surface per-feature on/off (FR-9.2).
- **Interface**: `register(plugin)`, `enable(id)`, `disable(id)`, `enabled() -> [PluginId]`.

### B7. LinkLogger
- **Purpose**: Structured logging without leaking data.
- **Responsibilities**: Timestamp + correlation id + level + message; **never log bodies/numbers/contacts/tokens** (CC-PRIV / SECURITY-03); log security events (failed pairing/auth, SECURITY-14).
- **Interface**: `info/debug/warn/error(event, fields)`.

---

## C. Feature Plugins (one module per capability, on both sides as applicable)

| Plugin | Android responsibilities | Mac responsibilities | Stories |
|---|---|---|---|
| **C1 NotificationPlugin** | Capture notifications via `NotificationListenerService`; apply per-app allowlist; send `notif.posted` | Render as native macOS notifications/feed (read-only v1) | US-3.1–3.2 (US-3.3 Later) |
| **C2 SmsPlugin** | Read incoming SMS/MMS + thread history via Telephony APIs; send `sms.received` / `sms.thread` | Display threads + messages (read-only v1) | US-4.1–4.2 (US-4.3 Later) |
| **C3 FileTransferPlugin** | Send/receive files over a binary stream; write to configured destination | Drag-and-drop send; receive to destination; progress UI | US-5.1–5.3 |
| **C4 ClipboardPlugin** | Read/set clipboard; honor sync mode | Read/set clipboard; honor sync mode | US-6.1–6.2 |
| **C5 ScreenMirrorPlugin** | Capture via `MediaProjection`, encode H.264/H.265 (`MediaCodec`), stream frames; capture indicator | Decode + render live view; start/stop (view-only v1) | US-7.1–7.2 (US-7.3 Later) |
| **C6 CallPlugin** | Observe call state (`InCallService`/`TelephonyManager`), resolve contacts; execute answer/decline/dial; send `call.*`; (audio = Bluetooth HFP, OS-level) | Caller-ID popup, answer/decline/dial UI, call history; guide one-time BT setup | US-8.1–8.5 |
| **C7 SettingsPermissions** | Permission prompts + per-feature toggles; persistence | Permission prompts + per-feature toggles; persistence | US-9.1–9.3 |

---

## D. App Shells

### D1. Mac App Shell (SwiftUI)
- **Purpose**: Native menu-bar-first UX + windowed views.
- **Responsibilities**: Menu-bar status, windows (Messages, Files, Screen mirror, Calls, Settings), onboarding flow; host Core + plugins; coordinate UI ↔ services.
- **Interface**: `AppCoordinator` driving `ConnectionService`, feature view-models.

### D2. Android App Shell (Kotlin/Compose)
- **Purpose**: Compose UI + always-on link.
- **Responsibilities**: **LinkForegroundService** to keep the connection alive (FR-2.2); Compose screens for pairing/permissions/settings/status; host Core + plugins.
- **Interface**: `LinkForegroundService`, Compose screens + view-models over the same services.

---

## Component Inventory Summary
- **Shared protocol**: Message Envelope, Binary Frame, Type Registry (3)
- **Core (per app)**: Discovery, Pairing, Connection, Router, SecureStore, PluginRegistry, Logger (7)
- **Feature plugins**: Notifications, SMS, Files, Clipboard, Screen Mirror, Calls, Settings/Permissions (7)
- **App shells**: Mac shell, Android shell (2)
