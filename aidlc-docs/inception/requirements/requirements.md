# Requirements — android_bridge

## Intent Analysis

- **User request**: Build an all-in-one continuity hub between a Samsung Galaxy (Android) and an Apple Silicon Mac — the Android↔Mac equivalent of Apple Continuity. Covers SMS, notification mirroring, file drag-and-drop, clipboard sync, screen mirroring, and phone-call control, with native Mac polish and seamless calls.
- **Request type**: New Project (greenfield).
- **Scope estimate**: Cross-system (two native apps — Android + macOS — plus a shared device-link protocol).
- **Complexity estimate**: Complex (multiple OS subsystems: telephony, notifications, screen capture, Bluetooth, networking, security/pairing).
- **Requirements depth**: Comprehensive.

## Decisions Locked (from clarification Q1–Q13)

| Area | Decision |
|---|---|
| Audience / distribution | Personal use, **open-sourced** code. No app-store / notarization / release engineering in v1; clean architecture so it could go public later. |
| Connectivity | **Local Wi-Fi/LAN, peer-to-peer, no servers** for all data. **Bluetooth HFP** carries call audio only. USB is a possible later enhancement. |
| v1 feature set | All features **except screen control**. View-only screen mirroring is in v1; tap/type-back control is deferred to a later milestone. |
| Calls | Accept the Android constraint: **call audio via Bluetooth HFP**; the app provides caller-ID, contact name, answer/decline/dial, and call history over the local link. Must feel seamless. |
| Samsung APIs | **Generic Android public APIs only.** No DeX/Flow/Knox dependencies. |
| Messages/notifications interactivity | **Read-only in v1** — both notifications and SMS are mirrored to the Mac for viewing only; reply/send happens on the phone. Architecture leaves SMS send + notification quick-reply open for a later milestone. |
| Minimum Android | **Android 13+** (API 33). Primary device runs Android 16. |
| Pairing & trust | **QR-code pairing + per-device TLS certificates, trust-on-first-pair, no accounts** (KDE-Connect-style mTLS over the local link). |
| Mac stack | **SwiftUI** menu-bar + windowed app (AppKit interop where needed). |
| Android stack | **Kotlin + Jetpack Compose**, foreground service for the device link. |
| Security extension | **Enabled** (blocking). |
| Resiliency extension | **Disabled.** |
| Property-Based Testing extension | **Partial** — enforced for pure functions and serialization round-trips (PBT-02, PBT-03, PBT-07, PBT-08, PBT-09). |

---

## Functional Requirements

### FR-1 — Device Pairing & Trust
- FR-1.1: A Mac and an Android device pair via a **QR code** (shown on one device, scanned/entered on the other) on the same local network.
- FR-1.2: On first pair, each device generates a **per-device TLS certificate/key pair**; the peer's certificate is **pinned** (trust-on-first-use). No cloud account is involved.
- FR-1.3: All subsequent connections require **mutual TLS** against the pinned certificates; unknown/unpinned devices are rejected.
- FR-1.4: A user can **view paired devices** and **unpair** (revoke trust) from either app.
- FR-1.5: Pairing keys/certificates are stored in **secure OS key storage** (macOS Keychain, Android Keystore / EncryptedSharedPreferences).

### FR-2 — Device Discovery & Connection
- FR-2.1: Devices **discover each other on the LAN** (e.g., mDNS/Bonjour or UDP broadcast) without manual IP entry.
- FR-2.2: The Android app runs a **foreground service** to keep the link alive and show an ongoing status notification.
- FR-2.3: Connection state (connected / reconnecting / disconnected) is **visible** on both the Mac menu-bar and the Android app.
- FR-2.4: On transient network loss, the link **auto-reconnects** when both devices are reachable again (ordinary reconnect/retry; resiliency baseline not applied).

### FR-3 — Notification Mirroring (read-only in v1)
- FR-3.1: Android notifications are **mirrored to the Mac** (app name, title, text, icon, timestamp) via the Android `NotificationListenerService`.
- FR-3.2: Notifications appear as **native macOS notifications / a Mac-side feed**.
- FR-3.3: v1 is **read-only** (no dismiss/quick-reply from the Mac). The protocol and data model are designed so two-way notification actions can be added later without redesign.
- FR-3.4: The user can choose **which apps** are allowed to mirror notifications (allowlist/denylist).

### FR-4 — SMS / MMS Messaging (read-only in v1)
- FR-4.1: Incoming **SMS/MMS** are delivered to the Mac in real time (sender, contact name if resolvable, body, timestamp, attachments for MMS).
- FR-4.2: The user can **read SMS conversation history** on the Mac.
- FR-4.3: Messages are organized **by conversation/thread**.
- FR-4.4: v1 is **read-only** — composing/sending SMS from the Mac is **deferred** (reply happens on the phone). The data model and protocol are designed so Mac-side send can be added later without redesign.
- FR-4.5: RCS is explicitly **out of scope** (locked to Google Messages; SMS/MMS only).

### FR-5 — File Transfer (drag-and-drop, both directions)
- FR-5.1: The user can **drag files from the Mac onto the app** to send them to the Android device, and vice versa.
- FR-5.2: Transfers show **progress** and a **completion / failure** result.
- FR-5.3: Received files land in a **configurable destination** (e.g., Downloads) on each platform.
- FR-5.4: Large files transfer over the **LAN link** (not Bluetooth).

### FR-6 — Clipboard Sync
- FR-6.1: **Text clipboard** content can be synced between devices.
- FR-6.2: Sync direction is **user-controllable** (auto-sync vs. manual push) to avoid surprises; default behavior to be settled in design.
- FR-6.3: Clipboard payloads travel over the **encrypted LAN link**.

### FR-7 — Screen Mirroring (view-only in v1)
- FR-7.1: The Mac can **display a live mirror** of the Android screen, captured via the Android **MediaProjection** API and H.264/H.265-encoded (`MediaCodec`).
- FR-7.2: The stream runs over the **LAN**; quality/bitrate adapts to keep latency low (target: responsive, scrcpy-class).
- FR-7.3: v1 is **view-only**. **Screen control (injecting taps/keys back into the phone) is explicitly deferred** to a later milestone (will require an Accessibility-service or ADB-assisted approach — to be decided when scoped).
- FR-7.4: The user can **start/stop mirroring** from either app, with a clear on-phone indicator that capture is active.

### FR-8 — Phone Calls (controls on Mac, audio over Bluetooth)
- FR-8.1: When a call **rings on the phone**, a **caller-ID popup** appears on the Mac (number, resolved contact name, photo if available).
- FR-8.2: The user can **answer / decline** the incoming call from the Mac.
- FR-8.3: The user can **place a call** (dial / pick a contact) from the Mac.
- FR-8.4: **Call audio is carried by Bluetooth Hands-Free Profile (HFP)** between the Mac and phone — the app does not stream call audio over Wi-Fi (Android does not permit this without root).
- FR-8.5: The pairing/onboarding flow **guides the user through the one-time Bluetooth setup** so calls subsequently "just work" (seamless, per Q4).
- FR-8.6: The Mac shows **call history** (incoming/outgoing/missed) sourced from the phone.
- FR-8.7: Contact-name resolution requires **read access to contacts** on Android.

### FR-9 — Settings & Permissions
- FR-9.1: Each app surfaces the **OS permissions** it needs and guides the user to grant them (Android: notification access, SMS, contacts, screen capture, foreground service, Bluetooth; macOS: notifications, network, Bluetooth, accessibility only if/when control is added).
- FR-9.2: The user can **enable/disable each feature** independently (notifications, SMS, files, clipboard, screen, calls).
- FR-9.3: Settings persist across restarts.

---

## Non-Functional Requirements

### NFR-1 — Privacy & Data Locality
- NFR-1.1: **No data leaves the two paired devices.** No servers, no cloud relay, no telemetry to third parties (v1).
- NFR-1.2: All device-to-device traffic is **encrypted in transit (mutual TLS, TLS 1.2+)** over the LAN. *(SECURITY-01)*
- NFR-1.3: Sensitive data persisted on either device (pairing keys, message/contact/call caches) is **encrypted at rest** using OS-managed secure storage. *(SECURITY-01)*

### NFR-2 — Security (Security extension ENABLED — blocking)
Applicable baseline rules and how they map to this local, server-less app:
- **SECURITY-01** (encryption at rest & in transit): mTLS on the wire; Keychain/Keystore for keys and caches. **Applicable.**
- **SECURITY-03** (application logging): structured logging on both apps; **no secrets/PII (message bodies, numbers, tokens) in logs.** **Applicable.**
- **SECURITY-05** (input validation): **every protocol message received over the wire is untrusted input** and must be validated (type, size bounds, format) before processing. **Applicable.**
- **SECURITY-06 / SECURITY-08** (least privilege / app-level access control): only **paired, mTLS-authenticated** devices may invoke any capability; deny-by-default; each request authorized against granted feature permissions. **Applicable.**
- **SECURITY-09** (hardening / misconfiguration): no default credentials; generic user-facing errors (no stack traces / internal paths). **Applicable.**
- **SECURITY-10** (supply chain): pinned dependencies + lockfiles (Swift Package Manager resolved file; Gradle version catalog + dependency lock), dependency vulnerability scanning in CI, SBOM for releases, no `latest`/unpinned CI images. **Applicable.**
- **SECURITY-12** (credential management): pairing secrets in secure storage; **no hardcoded secrets** in source or build files. **Applicable.**
- **SECURITY-13** (software/data integrity): **safe deserialization** of wire messages (allowlist of message types; no unsafe/native deserialization of untrusted bytes). **Applicable.**
- **SECURITY-14** (alerting/monitoring): log security-relevant local events (failed pairing/auth attempts) without PII; full cloud-style alerting is **N/A** (no cloud). **Partially applicable.**
- **SECURITY-15** (fail-safe defaults): **fail closed** — on any auth/validation error, deny the connection or drop the message; clean up resources on error paths. **Applicable.**
- **N/A for this project** (no web tier / cloud infra): SECURITY-02 (load balancers/CDN), SECURITY-04 (HTTP security headers for HTML endpoints), SECURITY-07 (cloud VPC/security groups), and the cloud-IAM portions of SECURITY-06. To be confirmed per-stage.

### NFR-3 — Performance & Latency
- NFR-3.1: Screen mirroring target **end-to-end latency ≤ ~80 ms** on a healthy 5 GHz LAN; adaptive bitrate to sustain a smooth frame rate.
- NFR-3.2: Notification and SMS delivery to the Mac should feel **near-real-time** (sub-second under normal conditions).
- NFR-3.3: File transfer should saturate available LAN bandwidth rather than an artificial cap.
- NFR-3.4: The Android foreground service must keep **battery and memory overhead modest** when idle.

### NFR-4 — Usability & "Native Mac Polish"
- NFR-4.1: Mac app is a **menu-bar-first** experience with a windowed view for richer interactions (messages, file history, screen mirror).
- NFR-4.2: First-run **onboarding** walks the user through pairing, permission grants, and the one-time Bluetooth call setup.
- NFR-4.3: UI follows **native platform conventions** (macOS HIG; Material 3 on Android).
- NFR-4.4: Accessibility: keyboard navigation and screen-reader labels on the Mac; standard accessibility support on Android.

### NFR-5 — Reliability (baseline engineering; resiliency extension NOT applied)
- NFR-5.1: The link recovers from transient Wi-Fi drops via reconnect/retry.
- NFR-5.2: Partial failures (e.g., one feature's permission revoked) degrade gracefully without crashing the app.
- NFR-5.3: *Note:* the AWS resiliency baseline is **not enforced** (per Q12) — this is a local app, not a distributed cloud workload.

### NFR-6 — Portability & Maintainability
- NFR-6.1: **Generic Android** (API 33+) — no Samsung-specific APIs, so it can run on other Android phones later.
- NFR-6.2: The **device-link protocol** (message schema + transport) is a clearly separated layer shared in spirit by both apps, so features can be added without reworking transport.
- NFR-6.3: Open-source-ready: clean module boundaries, documented protocol, no proprietary lock-in.

### NFR-7 — Testability (PBT extension PARTIAL — enforced for pure functions & serialization)
- NFR-7.1: A **property-based testing framework** is selected per language and added as a dependency *(PBT-09)*: **fast-check**-equivalent for the chosen JS/TS tooling if any, **Kotest Property Testing** for Kotlin, **SwiftCheck** (or equivalent) for Swift.
- NFR-7.2: The **device-link message protocol must have round-trip PBT** (`decode(encode(x)) == x`) for every message type *(PBT-02)* — this is the primary PBT surface.
- NFR-7.3: **Invariant PBT** for pure transformation/normalization functions (e.g., clipboard normalization, message-thread grouping, file-chunking math) *(PBT-03)*.
- NFR-7.4: PBT uses **domain-appropriate generators** (valid message shapes, realistic payload sizes), not bare primitives *(PBT-07)*.
- NFR-7.5: PBT supports **shrinking + seed-logged reproducibility** and runs in CI *(PBT-08)*.
- NFR-7.6: PBT **complements** example-based integration/E2E tests; critical paths keep explicit example tests too.
- NFR-7.7: *Out of partial scope:* full stateful PBT (PBT-06), oracle testing (PBT-05), and idempotency PBT (PBT-04) are **advisory, non-blocking** under Partial mode.

---

## Out of Scope (v1)

- Screen **control** (tap/type back into the phone) — deferred; mirroring is view-only.
- **Remote / off-LAN** connectivity via a relay server — local network only.
- **RCS** messaging — SMS/MMS only.
- **Live call audio over Wi-Fi** — not possible without root; Bluetooth HFP is the audio path.
- **App-store distribution, notarization, multi-user onboarding/support** — open-source/sideload in v1.
- **Samsung-specific** features (DeX/Flow/Knox).
- **Sending SMS from the Mac** — read-only in v1; Mac-side send deferred to a later milestone (architected for).
- Two-way notification actions (dismiss / quick-reply) — architected for, not built in v1.

---

## Key Constraints (carried from research)

- Android exposes **no API for live cellular call audio** to third-party apps without root → call audio must use **Bluetooth HFP**.
- **RCS** is locked to Google Messages; third-party apps get **SMS/MMS via Telephony APIs** only.
- **Screen control** without root requires either an **AccessibilityService** or **ADB-assisted** input injection — deferred decision.
- Bluetooth throughput (~1–3 Mbps real-world) is **insufficient for screen/data** → those go over Wi-Fi/LAN.

---

## Open Items (carried into design)

_(none — all resolved below.)_

## Resolved at Approval (2026-06-27)
- **SMS is read-only in v1** (per user): receive + read history on the Mac; sending deferred. (Resolves the prior Q6 interpretation.)

## Resolved at Units Generation (2026-06-30)
- **Clipboard default = manual push** (FR-6.2 / US-6.2): copy stays local; the user explicitly pushes. Auto-sync is available as an opt-in setting. (Privacy-first, least-surprising; matches NFR-1.)
