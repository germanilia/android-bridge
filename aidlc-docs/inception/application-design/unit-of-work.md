# Unit of Work — android_bridge

Decomposition of the system into **12 units** built foundation-first. A "unit" is a logical
grouping of stories built together — here, **modules within two native apps + a shared
protocol**, not deployable services (this is two apps + a P2P link, not microservices).

**Decisions applied** (unit-of-work-plan, 2026-06-30): Q1=A (7 separate feature units) ·
Q2=A (monorepo) · Q3=A (protocol = spec + 2 impls + PBT) · Q4=A (walking skeleton first) ·
Q5=A (clipboard default = manual push).

---

## Code Organization Strategy (greenfield, monorepo)

```
android_bridge/                  # repo root
├── protocol/                    # U1 — single source of truth for the wire contract
│   ├── PROTOCOL.md              #      language-neutral spec (envelope, frames, type registry)
│   ├── swift/                   #      Swift reference impl (codecs) — consumed by mac/
│   └── kotlin/                  #      Kotlin reference impl (codecs) — consumed by android/
├── mac/                         # macOS app (SwiftUI) — Xcode / Swift Package Manager
│   ├── Core/                    #      Pairing, Connection, Discovery, Router, SecureStore, Logger
│   ├── Plugins/                 #      Notification, Sms, FileTransfer, Clipboard, ScreenMirror, Call, Settings
│   ├── Services/                #      Discovery/Pairing/Connection/Message + per-feature services
│   └── App/                     #      AppCoordinator, menu-bar, windows, onboarding
├── android/                     # Android app (Kotlin/Compose) — Gradle (version catalog + lockfile)
│   ├── core/                    #      same Core responsibilities (Kotlin)
│   ├── plugins/                 #      same 7 plugins (Kotlin)
│   ├── services/                #      same services + LinkForegroundService
│   └── app/                     #      Compose screens, onboarding, DI wiring
├── aidlc-docs/                  # AI-DLC documentation (this workflow)
└── README.md                    # build/run for both apps (US-10.1)
```

- **Protocol is shared in spirit, implemented per language** (Q2/Q3): `PROTOCOL.md` is canonical;
  `protocol/swift` and `protocol/kotlin` are hand-written codecs kept in sync with the spec, each
  carrying the round-trip PBT (`decode(encode(x)) == x`, PBT-02).
- **Within each app**: acyclic layering `App → Services → Plugins → Core → Protocol/mTLS`.
- **Security baseline** (ON): dependency pinning + lockfiles (SPM `Package.resolved`, Gradle
  version catalog + lockfile), no `latest` images in CI, SBOM at release (SECURITY-10).

---

## Units

### U1 — Protocol / Transport core  *(foundation)*
- **Responsibilities**: Message Envelope `{id,type,protocolVersion,payload}`; Binary Frame
  `{streamId,sequence,length,flags}`; Message Type Registry + per-type validation; length-prefixed
  JSON control codec; binary frame codec. Deliverable per Q3: `PROTOCOL.md` + Swift + Kotlin impls.
- **Stories**: US-10.2.  **Depends on**: nothing.
- **Primary PBT-02 surface** (round-trip both languages); PBT-03 for any pure transforms.
- **Security**: SECURITY-05/-13 (validation + safe deserialization) start here.

### U2 — Pairing & Security  *(foundation)*
- **Responsibilities**: per-device TLS identity (keypair + self-signed cert); QR pairing
  (create/consume); cert pinning / trust-on-first-use; trusted-device list; SecureStore
  (Keychain / Keystore + EncryptedSharedPreferences). PairingManager, SecureStore.
- **Stories**: US-1.1, US-1.2, US-1.3.  **Depends on**: U1.
- **Security**: SECURITY-01/-12 (encryption at rest), -06/-08 (trust).

### U3 — Discovery & Connection  *(foundation)*
- **Responsibilities**: DeviceDiscovery (mDNS — `NWBrowser`/`NsdManager`); ConnectionManager
  (mTLS against pinned certs, reject unpinned, multiplex control + binary streams, heartbeat,
  auto-reconnect); MessageRouter (validate + dispatch, fail-closed drop); **Android
  LinkForegroundService**; connection-state surfacing.
- **Stories**: US-2.1, US-2.2, US-2.3, US-2.4, US-10.3.  **Depends on**: U1, U2.
- **Security**: SECURITY-06/-08/-15, CC-SEC/CC-VALID enforced here.

> **Walking-skeleton checkpoint (Q4)**: after U1–U3, build a thin end-to-end path —
> pair, connect, and exchange one trivial round-trip message visible in both UIs — before
> building feature units. De-risks the cross-device plumbing early.

### U4 — Notifications  *(feature, read-only v1)*
- **Responsibilities**: Android `NotificationListenerService` capture + per-app allowlist →
  `notif.posted`; Mac renders native notifications/feed. NotificationPlugin + NotificationService.
- **Stories**: US-3.1, US-3.2.  **Depends on**: U3.  **[Later]**: US-3.3 (actions) — interface left open.

### U5 — SMS / MMS  *(feature, read-only v1)*
- **Responsibilities**: Android Telephony read of incoming SMS/MMS + thread history →
  `sms.received` / `sms.thread`; Mac renders threads. SmsPlugin + MessagingService.
- **Stories**: US-4.1, US-4.2.  **Depends on**: U3.  **[Later]**: US-4.3 (send) — interface left open.

### U6 — File Transfer  *(feature)*
- **Responsibilities**: bidirectional file transfer over binary stream (FrameCodec); offer/accept,
  progress, configurable destination. FileTransferPlugin + FileTransferService.
- **Stories**: US-5.1, US-5.2, US-5.3.  **Depends on**: U3 (streams).

### U7 — Clipboard  *(feature)*
- **Responsibilities**: text clipboard read/set; sync-mode setting. **Default = manual push (Q5)**;
  auto-sync is opt-in. ClipboardPlugin + ClipboardService.
- **Stories**: US-6.1, US-6.2.  **Depends on**: U3.

### U8 — Screen Mirror  *(feature, view-only v1)*
- **Responsibilities**: Android `MediaProjection` capture + `MediaCodec` H.264/H.265 encode →
  frame stream; Mac decode + render; start/stop; on-phone capture indicator; adaptive bitrate
  (NFR-3.1 ≤ ~80 ms). ScreenMirrorPlugin + ScreenMirrorService.
- **Stories**: US-7.1, US-7.2.  **Depends on**: U3 (streams).  **[Later]**: US-7.3 (control) — open.

### U9 — Calls  *(feature; audio via BT HFP)*
- **Responsibilities**: call-state observation (`InCallService`/`TelephonyManager`), contact
  resolution, answer/decline/dial, call history → `call.*`; Mac caller-ID popup, controls,
  history; onboarding hint for one-time BT-HFP pairing. CallPlugin + CallService. **Audio is
  Bluetooth HFP at the OS level — never a protocol message.**
- **Stories**: US-8.1, US-8.2, US-8.3, US-8.4, US-8.5.  **Depends on**: U3.

### U10 — Settings & Permissions  *(cross-cutting feature)*
- **Responsibilities**: per-feature enable/disable toggles; guided permission prompts per platform;
  graceful degradation when a permission is missing/revoked; persistence. SettingsPermissions +
  SettingsService + PermissionService + PluginRegistry.
- **Stories**: US-9.1, US-9.2, US-9.3.  **Depends on**: U3 (light); cross-cuts U4–U9.
- **Security**: SECURITY-06 (least privilege), -15 (fail-closed degradation).

### U11 — Mac App Shell (SwiftUI)  *(integration)*
- **Responsibilities**: menu-bar-first UX + windows (Messages, Files, Screen, Calls, Settings);
  onboarding flow (pairing → permissions → one-time BT setup); AppCoordinator wiring Core +
  plugins + services + view-models. README build/run for Mac.
- **Stories**: US-10.1 (Mac portion).  **Depends on**: U2–U10.

### U12 — Android App Shell (Compose)  *(integration)*
- **Responsibilities**: Compose screens (pairing/permissions/settings/status); onboarding; hosts
  the LinkForegroundService from U3; DI wiring of Core + plugins + services. README build/run for Android.
- **Stories**: US-10.1 (Android portion).  **Depends on**: U2–U10.

---

## Summary
- **Foundation (3)**: U1 Protocol · U2 Pairing & Security · U3 Discovery & Connection.
- **Features (7)**: U4 Notifications · U5 SMS · U6 Files · U7 Clipboard · U8 Screen Mirror · U9 Calls · U10 Settings/Permissions.
- **Shells (2)**: U11 Mac · U12 Android.
- **All 29 v1 stories assigned**; 3 [Later] stories intentionally unassigned (interfaces kept open).
