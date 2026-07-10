# android_bridge — Design & Architecture Recap

> A single-page recap of what we're building, the decisions that shape it, and the
> architecture as designed so far. Sourced from the requirements, workflow plan,
> and application-design artifacts under `aidlc-docs/inception/`.
> **Status: U1-U12 construction and build/test complete. Current work is post-construction feature hardening, starting with phone-call control and Bluetooth HFP feasibility.**

---

## 1. What we're building

The Android↔Mac equivalent of **Apple Continuity** — an all-in-one continuity hub
between a **Samsung Galaxy (Android 13+)** and an **Apple Silicon Mac**.

Two native apps talk **directly, peer-to-peer, over the local Wi-Fi/LAN** (no servers,
no cloud). Call **audio** rides Bluetooth HFP; everything else flows over an encrypted
device-link protocol.

**v1 capabilities:** notification mirroring · SMS/MMS mirroring · file drag-and-drop ·
clipboard sync · screen mirroring (view-only) · phone-call control (caller-ID,
answer/decline/dial, history).

---

## 2. The decisions that shape everything

These were locked during Requirements Analysis (Q1–Q13) and Application Design (Q1–Q4).

| # | Decision | Why it matters |
|---|----------|----------------|
| **Local-only, P2P, no servers** | All data stays on the two paired devices over the LAN | No backend, no cloud infra → Infrastructure Design is **skipped** |
| **Bluetooth HFP for call audio** | Android exposes no API for live cellular call audio without root | Audio is OS-level, **never** a protocol message — only call metadata/control flows over the link |
| **Generic Android public APIs only** | No DeX / Flow / Knox | Portable to any Android 13+ phone later |
| **QR pairing + per-device mTLS, trust-on-first-pair, no accounts** | KDE-Connect-style mutual TLS, pinned certs | Security model is the foundation of the whole link |
| **SwiftUI (Mac) · Kotlin + Compose (Android)** | Native polish on both sides | Mac = menu-bar-first; Android = foreground service keeps link alive |
| **Read-only v1 for SMS & notifications** | Mirror to Mac for viewing; reply on the phone | Send/quick-reply deferred but **architected for** |
| **Screen mirroring is view-only** | Tap/type-back control deferred | Control needs Accessibility/ADB — scoped later |
| **Single mTLS session, multiplexed** (Q1) | One connection: typed JSON control + binary frames for bulk | Simplest trust model; channels for control vs. file/screen |
| **One hand-written schema, length-prefixed JSON** (Q2) | No codegen toolchain | Easy to read, debug, and round-trip property-test |
| **Feature-plugin modules on a shared Core** (Q3) | Each capability is self-contained on both sides | Clean unit boundaries, contributor-friendly |
| **mDNS / Bonjour discovery** (Q4) | `NWBrowser` (Mac) / `NsdManager` (Android) | Zero-config peer discovery on the LAN |
| **Open-source-ready, personal use** | No app-store / notarization in v1 | Clean module boundaries so it *could* go public |

**Extensions:** Security Baseline **ON (blocking)** · Resiliency Baseline **OFF** ·
Property-Based Testing **PARTIAL** (protocol round-trips + pure functions).

---

## 3. Architecture at a glance

```
        Mac App (SwiftUI)                              Android App (Kotlin/Compose)
   ┌─────────────────────────┐                      ┌─────────────────────────────┐
   │  UI: menu-bar + windows │                      │  UI: Compose screens        │
   ├─────────────────────────┤                      ├─────────────────────────────┤
   │  Services (orchestration)│                     │  Services + ForegroundService│
   ├─────────────────────────┤                      ├─────────────────────────────┤
   │  Feature Plugins         │                      │  Feature Plugins            │
   ├─────────────────────────┤                      ├─────────────────────────────┤
   │  Core: Conn · Pair ·     │                      │  Core: Conn · Pair ·        │
   │  Router · SecureStore ·  │                      │  Router · SecureStore ·     │
   │  Discovery · Logger      │                      │  Discovery · Logger         │
   └───────────┬─────────────┘                      └──────────────┬──────────────┘
               │                                                    │
               │   ┌────────────────────────────────────────────┐ │
               └───┤  Device-Link Protocol over MUTUAL TLS (LAN) ├─┘
                   │  length-prefixed JSON control + binary frames│
                   └────────────────────────────────────────────┘
               ┌────────────────────────────────────────────────┐
               │  Bluetooth HFP — call audio ONLY (OS-level)     │
               └────────────────────────────────────────────────┘
```

**Layering (acyclic):** `UI → Services → Plugins → Core → Protocol/mTLS`.
The *only* cross-device coupling is the protocol (plus OS-level Bluetooth for audio).
No app ever calls the other directly — it's all messages and streams.

---

## 4. The three logical pieces

### A. Shared Device-Link Protocol (the contract, mirrored in both codebases)
- **Message Envelope** — `{ id, type, protocolVersion, payload }`, length-prefixed JSON. *Primary PBT target: `decode(encode(x)) == x`.*
- **Binary Frame** — header `{ streamId, sequence, length, flags }` + bytes, for file chunks & screen frames.
- **Message Type Registry** — single source of truth: `pair.request`, `notif.posted`, `sms.received`, `file.offer`, `clip.update`, `screen.start`, `call.incoming`, `call.action`, … + per-type schema/validation.

### B. Core (same responsibilities, native per platform)
| Component | Role |
|-----------|------|
| **DeviceDiscovery** | Advertise + browse for the peer via mDNS/Bonjour |
| **PairingManager** | Generate TLS keypair/cert, QR pair, pin peer (TOFU), manage trusted list |
| **ConnectionManager** | Establish mTLS, reject unpinned peers, multiplex control+streams, heartbeat, auto-reconnect |
| **MessageRouter** | Validate + safe-deserialize inbound, dispatch by `type`, drop malformed (fail-closed) |
| **SecureStore** | Encrypted persistence — Keychain (Mac) / Keystore + EncryptedSharedPreferences (Android) |
| **PluginRegistry** | Register / enable / disable feature plugins |
| **LinkLogger** | Structured logging that **never** logs bodies/numbers/contacts/tokens; logs security events |

### C. Feature Plugins (one module per capability)
| Plugin | Android side | Mac side | v1 scope |
|--------|--------------|----------|----------|
| **Notification** | `NotificationListenerService` + app allowlist → `notif.posted` | Native macOS notifications/feed | read-only |
| **SMS** | Telephony APIs → `sms.received` / thread history | Render threads | read-only (send deferred) |
| **File Transfer** | Send/receive over binary stream | Drag-and-drop, progress UI | full |
| **Clipboard** | Read/set, honor sync mode | Read/set, honor sync mode | full |
| **Screen Mirror** | `MediaProjection` + `MediaCodec` (H.264/265), capture indicator | Decode + render live view | view-only (control deferred) |
| **Call** | `InCallService`/`TelephonyManager`, resolve contacts, answer/decline/dial | Caller-ID popup, controls, history, BT setup hint | full (audio = HFP) |
| **Settings/Permissions** | Permission prompts + per-feature toggles | Same | full |

### App Shells
- **Mac** — `AppCoordinator` driving menu-bar status, windows (Messages, Files, Screen, Calls, Settings), onboarding.
- **Android** — `LinkForegroundService` keeps the link alive + ongoing notification; Compose screens.

---

## 5. How data flows (representative)

- **Pairing:** UI → `PairingService` (QR) → `PairingManager` pins peer → `SecureStore` → `ConnectionService.connect()`.
- **Inbound (e.g. SMS):** peer → `ConnectionManager` (mTLS) → `MessageRouter.route()` (validate) → `MessagingService` → UI.
- **Outbound (e.g. answer call):** UI → `CallService.sendAction(answer)` → `ConnectionService.send(call.action)` → peer `CallPlugin.answer()`; audio via HFP.
- **Bulk (file/screen):** `…Service.openStream()` → `FrameCodec` frames over the mTLS session → peer reassembles → write/render.

---

## 6. Security & privacy mapping (Security extension ON)

| Concern | Where it lives | Rule |
|---------|----------------|------|
| Encrypt in transit, reject unpinned | ConnectionManager (mTLS) | SECURITY-01 / -06 / -08 |
| Encrypt at rest | SecureStore (Keychain/Keystore) | SECURITY-01 / -12 |
| Validate + safe-deserialize every inbound message | MessageRouter + Type Registry | SECURITY-05 / -13 |
| Fail closed (drop malformed, deny on error) | MessageRouter / ConnectionManager | SECURITY-15 |
| No PII in logs; log security events | LinkLogger | SECURITY-03 / -14 |
| Least privilege (per-feature permissions + toggles) | SettingsPermissions | SECURITY-06 |
| Supply chain (pinned deps, lockfiles, scanning, SBOM) | build/CI | SECURITY-10 |

**N/A** (no cloud/web tier): SECURITY-02 (LB/CDN), -04 (HTTP headers), -07 (VPC), cloud-IAM parts of -06.

---

## 7. Testability (PBT partial)

- **Protocol codecs** → round-trip PBT `decode(encode(x)) == x` (PBT-02) — the primary surface.
- **Pure transforms** (clipboard normalization, thread grouping, file-chunk math) → invariant PBT (PBT-03).
- Domain generators (PBT-07), shrinking + seeded CI runs (PBT-08), framework picked at NFR Requirements (Kotest / SwiftCheck).
- PBT **complements** example-based integration/E2E tests on critical paths.

---

## 8. Deferred (architected for, not built in v1)

- **SMS send from Mac** (US-4.3)
- **Notification quick-reply / dismiss** from Mac (US-3.3)
- **Screen control** — inject taps/keys back into the phone (US-7.3; needs Accessibility/ADB)
- **USB transport**, **off-LAN/relay** connectivity, **RCS**, **live call audio over Wi-Fi** — all out of scope.

The protocol and plugin interfaces are shaped to accept these later **without redesign**.

---

## 9. Where the workflow stands

| Phase | Stage | Status |
|-------|-------|--------|
| 🔵 Inception | Workspace Detection → Requirements → User Stories → Workflow Planning → Application Design → Units Generation | ✅ Done |
| 🟢 Construction | U1–U12 per-unit design and code generation | ✅ Done |
| | Infrastructure Design | ⏭️ Skipped (no cloud) |
| | Build & Test | ✅ Done; latest Android and Mac tests passed 2026-07-05 |
| 🟡 Operations | Operations | ⬜ Placeholder |
| 🔁 Post-construction | Call-control compatibility fix | ✅ Done |
| | Call control hardening | ⬜ Next |
| | Bluetooth HFP feasibility spike | ⬜ Next major investigation |

Implemented units: Protocol/Transport core · Pairing & Security · Discovery & Connection · Notifications · SMS · Files · Clipboard · Screen Mirror · Calls · Settings/Permissions · Mac app shell · Android app shell.

Next implementation plan: `aidlc-docs/NEXT-FEATURE-IMPLEMENTATION.md`.

---

## 10. Source artifacts

- **Requirements:** `aidlc-docs/inception/requirements/requirements.md`
- **User Stories / Personas:** `aidlc-docs/inception/user-stories/`
- **Workflow plan:** `aidlc-docs/inception/plans/execution-plan.md`
- **Application design:** `aidlc-docs/inception/application-design/` (`application-design.md`, `components.md`, `component-methods.md`, `services.md`, `component-dependency.md`)
- **State / audit:** `aidlc-docs/aidlc-state.md`, `aidlc-docs/audit.md`
