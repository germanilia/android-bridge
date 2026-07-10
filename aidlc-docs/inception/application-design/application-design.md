# Application Design (Consolidated) — android_bridge

This consolidates `components.md`, `component-methods.md`, `services.md`, and `component-dependency.md`. Detailed business logic is deferred to per-unit Functional Design (CONSTRUCTION).

## 1. Overview
A local-only, peer-to-peer continuity hub between a Mac (SwiftUI) and an Android phone (Kotlin/Compose). Two native apps share a **Device-Link Protocol** carried over a single **mutual-TLS** session on the LAN. Each app is built as **feature-plugin modules on a shared Core**. Call **audio** uses **Bluetooth HFP** at the OS level; only call control/metadata flows over the protocol.

**Design drivers**: privacy (no servers, mTLS, encrypted-at-rest), native polish (SwiftUI/Compose), portability (generic Android 13+), testability (round-trip PBT on the protocol), security baseline (validation, least privilege, fail-closed, no-PII logging).

## 2. Architecture Decisions (from plan Q1–Q4)
- **Q1**: single mTLS session, multiplexed JSON control messages + binary frames for bulk.
- **Q2**: one documented schema, length-prefixed JSON control, hand-implemented per language.
- **Q3**: feature-plugin modules on a shared Core.
- **Q4**: mDNS/Bonjour discovery.

## 3. Components
- **Shared protocol**: Message Envelope, Binary Frame, Message Type Registry.
- **Core (per app)**: DeviceDiscovery, PairingManager, ConnectionManager, MessageRouter, SecureStore, PluginRegistry, LinkLogger.
- **Feature plugins**: Notification, SMS (read-only), File Transfer, Clipboard, Screen Mirror (view-only), Call (controls; audio via BT HFP), Settings/Permissions.
- **App shells**: Mac (SwiftUI menu-bar + windows), Android (Compose + LinkForegroundService).
(See `components.md` for responsibilities and interfaces.)

## 4. Methods
Method signatures for protocol codecs, Core, plugins, and shells are in `component-methods.md`. Protocol codecs carry the primary PBT target (`decode(encode(x)) == x`, PBT-02).

## 5. Services & Orchestration
DiscoveryService, PairingService, ConnectionService, MessageRouter facade, per-feature services, PermissionService. Representative flows (pairing, inbound message, outbound action, bulk stream) are in `services.md`.

## 6. Dependencies & Data Flow
Acyclic layering UI → Services → Plugins → Core → Protocol/mTLS. Cross-device coupling is *only* the protocol (plus OS-level Bluetooth for audio). Matrix + Mermaid data-flow in `component-dependency.md`.

## 7. Story Coverage
| Epic | Components/Services |
|---|---|
| E1 Pairing & Trust | PairingManager, PairingService, SecureStore |
| E2 Discovery & Connection | DeviceDiscovery, ConnectionManager, DiscoveryService, ConnectionService, LinkForegroundService |
| E3 Notifications | NotificationPlugin, NotificationService |
| E4 SMS (read-only) | SmsPlugin, MessagingService |
| E5 File Transfer | FileTransferPlugin, FileTransferService, FrameCodec |
| E6 Clipboard | ClipboardPlugin, ClipboardService |
| E7 Screen Mirror (view-only) | ScreenMirrorPlugin, ScreenMirrorService, FrameCodec |
| E8 Calls | CallPlugin, CallService (+ OS Bluetooth HFP) |
| E9 Settings & Permissions | SettingsPermissions, SettingsService, PermissionService |
| E10 Maintainability/Portability | Shared protocol, plugin architecture, generic Android |

## 8. Security & Privacy Mapping (Security extension ON)
- **mTLS only / reject unpinned** — ConnectionManager (CC-SEC, SECURITY-06/-08).
- **Encrypted at rest** — SecureStore (SECURITY-01/-12).
- **Validate + safe-deserialize inbound** — MessageRouter + MessageTypeRegistry (SECURITY-05/-13).
- **Fail-closed** — drop malformed messages, deny on error (SECURITY-15).
- **No-PII logging** — LinkLogger (SECURITY-03); security events logged (SECURITY-14).
- **Least privilege** — per-feature permissions + toggles (SECURITY-06, US-9.x).
- **N/A** (no cloud/web): SECURITY-02, -04, -07, cloud-IAM parts of -06.

## 9. Testability Mapping (PBT partial)
- Protocol codecs → round-trip PBT (PBT-02) + invariant PBT for transforms (PBT-03).
- Domain generators for message types (PBT-07); shrinking + seeded CI runs (PBT-08); framework selected at NFR Requirements (PBT-09).

## 10. Deferred ([Later])
SMS send from Mac (US-4.3), notification actions (US-3.3), screen control (US-7.3) — protocol/plugin interfaces are shaped to accept them without redesign.

## 11. Preliminary Unit Hints (finalized in Units Generation)
Likely units: **Protocol/Transport core**, **Pairing & Security**, **Discovery & Connection (+ Android FG service)**, then per-feature units (Notifications, SMS, Files, Clipboard, Screen Mirror, Calls), plus **Mac app shell** and **Android app shell**. Shared Core + Protocol are foundational dependencies for all feature units.
