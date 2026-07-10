# Component Methods — android_bridge

Method signatures + high-level purpose + I/O types. **Business rules and detailed logic are deferred to per-unit Functional Design.** Signatures are language-neutral pseudocode (implemented in Swift on Mac, Kotlin on Android).

---

## Shared Device-Link Protocol

### MessageCodec (A1)
- `encode(message: Message) -> Bytes` — serialize a control message to length-prefixed JSON.
- `decode(bytes: Bytes) -> Message` — parse + validate envelope; throws on malformed (fail-closed).
- *PBT (PBT-02)*: `decode(encode(m)) == m` for all valid `m`.

### FrameCodec (A2)
- `encodeFrame(header: FrameHeader, payload: Bytes) -> Bytes`
- `decodeFrame(bytes: Bytes) -> (FrameHeader, Bytes)`
- `FrameHeader = { streamId: UInt, sequence: UInt, length: UInt, flags: UInt }`

### MessageTypeRegistry (A3)
- `schemaFor(type: MessageType) -> Schema`
- `validate(message: Message) -> ValidationResult` — type/size/format checks (SECURITY-05).

---

## Core

### DeviceDiscovery (B1)
- `startAdvertising(identity: DeviceIdentity) -> Void`
- `startBrowsing() -> Void`
- `onPeerFound(callback: (Endpoint) -> Void) -> Void`
- `stop() -> Void`

### PairingManager (B2)
- `generateIdentity() -> DeviceIdentity` — create TLS keypair + self-signed cert.
- `createPairingQR() -> QRPayload` — encode cert fingerprint + connection hint.
- `consumePairingQR(payload: QRPayload) -> PairResult` — verify + pin peer.
- `pinPeer(cert: Certificate, deviceId: DeviceId) -> Void`
- `listPaired() -> [PairedDevice]`
- `unpair(deviceId: DeviceId) -> Void`

### ConnectionManager (B3)
- `connect(endpoint: Endpoint) -> Void` — establish mutual TLS against pinned cert; reject unpinned (CC-SEC).
- `send(message: Message) -> Void`
- `openStream(streamId: UInt) -> Stream` — binary stream for bulk data.
- `onMessage(handler: (Message) -> Void) -> Void`
- `observeState() -> Stream<ConnectionState>` — connected / reconnecting / disconnected.
- `disconnect() -> Void`
- *Note*: auto-reconnect is internal behavior (FR-2.4).

### MessageRouter (B4)
- `register(type: MessageType, plugin: Plugin) -> Void`
- `route(message: Message) -> Void` — validate + safe-deserialize, dispatch; drop malformed (SECURITY-13/-15).
- `unregister(type: MessageType) -> Void`

### SecureStore (B5)
- `put(key: String, value: Bytes) -> Void`
- `get(key: String) -> Bytes?`
- `delete(key: String) -> Void`

### PluginRegistry (B6)
- `register(plugin: Plugin) -> Void`
- `enable(id: PluginId) -> Void`
- `disable(id: PluginId) -> Void`
- `enabled() -> [PluginId]`

### LinkLogger (B7)
- `log(level: Level, event: String, fields: [String: Redactable]) -> Void` — redacts sensitive fields (CC-PRIV).
- `securityEvent(event: SecurityEvent) -> Void`

---

## Feature Plugins (selected key methods)

### NotificationPlugin (C1)
- Android: `onNotificationPosted(sbn: StatusBarNotification) -> Void` → builds `notif.posted`; `isAllowed(pkg: String) -> Bool`.
- Mac: `displayNotification(n: NotificationPayload) -> Void`.

### SmsPlugin (C2)
- Android: `onSmsReceived(msg: SmsMessage) -> Void` → `sms.received`; `loadThread(threadId) -> SmsThread`.
- Mac: `renderThread(thread: SmsThread) -> Void`; `renderIncoming(msg: SmsPayload) -> Void`.
- *(SMS send — `sendSms(...)` — deferred [Later], US-4.3.)*

### FileTransferPlugin (C3)
- `offerFile(meta: FileMeta) -> TransferId` — sends `file.offer`.
- `sendFile(transferId: TransferId, source: FileHandle) -> Stream<Progress>`
- `receiveFile(offer: FileMeta) -> Stream<Progress>` — writes to configured destination.
- `setDestination(path: Path) -> Void`

### ClipboardPlugin (C4)
- `readClipboard() -> ClipboardContent`
- `applyClipboard(content: ClipboardContent) -> Void`
- `setSyncMode(mode: ClipboardSyncMode) -> Void` — auto vs manual (FR-6.2).

### ScreenMirrorPlugin (C5)
- Android: `startCapture(config: CaptureConfig) -> Stream<EncodedFrame>`; `stopCapture() -> Void`; shows capture indicator.
- Mac: `startRender(stream: Stream<EncodedFrame>) -> Void`; `stopRender() -> Void`.
- `CaptureConfig = { maxBitrate, codec, targetLatencyMs }` (NFR-3.1).
- *(Control/input injection — deferred [Later], US-7.3.)*

### CallPlugin (C6)
- Android: `observeCallState() -> Stream<CallEvent>`; `resolveContact(number) -> Contact?`; `answer()`, `decline()`, `dial(number) -> Void`; `loadHistory() -> [CallRecord]`.
- Mac: `showIncoming(call: CallInfo) -> Void`; `sendAction(action: CallAction) -> Void`; `renderHistory(records: [CallRecord]) -> Void`.
- *Audio is Bluetooth HFP (OS-level) — no protocol method.*

### SettingsPermissions (C7)
- `requestPermission(p: Permission) -> PermissionResult`
- `featureEnabled(f: Feature) -> Bool`
- `setFeatureEnabled(f: Feature, on: Bool) -> Void`
- `permissionStatus(p: Permission) -> Status` — drives graceful degradation (US-9.3).

---

## App Shells

### Mac AppCoordinator (D1)
- `start() -> Void`; `showWindow(w: WindowKind) -> Void`; `runOnboarding() -> Void`.

### Android LinkForegroundService (D2)
- `onStartCommand(...) -> Int` — start link + ongoing notification.
- `bindUi() -> ServiceBinder`; `stopLink() -> Void`.
