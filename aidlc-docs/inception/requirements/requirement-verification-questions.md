# Requirements Clarification Questions — android_bridge

Please answer each question by filling in the letter after the `[Answer]:` tag. For any question, you can pick the last option (Other) and describe your own answer.

**Already decided (not asked again):** build from scratch · targets Samsung Galaxy + Apple Silicon Mac · differentiators = all-in-one hub, seamless calls, native Mac polish · use AI-DLC to drive the build.

**STATUS: ANSWERED** — all 13 answered on 2026-06-27. See each `[Answer]:` tag and the "Recorded Answers" summary at the bottom.

---

## Question 1 — Audience / Distribution
Who is this for, and how far does it need to go? (Biggest scope driver.)

A) Personal use only — just your own Samsung + your own Mac, no app stores, no other users

B) Personal first, but built so it could become a public product later (clean architecture, but no store/release work in v1)

C) Public product from day one — Play Store + notarized Mac distribution, onboarding, support for many users

X) Other (please describe after [Answer]: tag below)

[Answer]: B — personal use, but the code will be open-sourced. Clean architecture; no app-store / release engineering in v1.

---

## Question 2 — Connectivity model
How should the two devices reach each other?

A) Local network only — both devices on the same Wi-Fi/LAN, fully peer-to-peer, no servers, most private (like KDE Connect)

B) Local network primary, with USB fallback when on the same machine (cable for reliability/low-latency screen + mirroring)

C) Local + remote — also works when phone and Mac are on different networks, via a relay server (more complex, needs cloud infra)

X) Other (please describe after [Answer]: tag below)

[Answer]: A (hybrid transport) — local Wi-Fi/LAN, fully peer-to-peer, no servers, for ALL data (notifications, SMS, files, clipboard, screen mirroring). Call AUDIO travels over Bluetooth Hands-Free Profile (HFP), since Bluetooth bandwidth cannot carry screen/data. USB is a possible later nicety, not v1.

---

## Question 3 — v1 (MVP) feature set
Which features must be in the **first working version**? (Pick the set; we'll sequence the rest into later milestones.)

A) Lean core: pairing + notification mirroring + SMS send/receive + file drag-and-drop + clipboard sync (no screen, no calls yet)

B) Core + screen mirroring & control (adds scrcpy-style mirroring on top of A)

C) Everything including calls in v1 (A + B + Bluetooth-based call experience) — largest v1

X) Other (please describe after [Answer]: tag below)

[Answer]: C, with one carve-out — everything in v1 EXCEPT screen *control* (tap/type back into the phone), which is deferred. Screen *mirroring* (view-only) stays in v1.

---

## Question 4 — Phone calls: accept the Bluetooth ceiling?
As researched: a third-party Android app **cannot** stream live cellular call audio over Wi-Fi without rooting. The realistic design is: **Mac pairs as a Bluetooth Hands-Free (HFP) speakerphone for audio**, and our app adds the polish — caller-ID popup on the Mac, answer/decline/dial from the Mac, contact names, call history. Is that acceptable?

A) Yes — Bluetooth HFP for audio + our app for caller-ID/controls is fine; make that experience as seamless as possible

B) Yes, but only if it feels native (no separate Bluetooth pairing dance — guide the user through it once, then it "just works")

C) No — calls are only worth doing if audio can route over Wi-Fi; if not, drop calls from scope entirely

X) Other (please describe after [Answer]: tag below)

[Answer]: A — accept the Bluetooth HFP audio path + on-Mac caller-ID/controls; make it as seamless as possible.

---

## Question 5 — Samsung-specific capabilities
Your phone is a Samsung Galaxy. Samsung exposes extra APIs (DeX, Samsung Flow, Knox) that generic Android lacks. Lean in or stay generic?

A) Stay generic Android (Android 13+ public APIs only) — portable to any Android phone later, simpler, no Samsung lock-in

B) Generic core, but opportunistically use Samsung APIs where they clearly improve the experience (graceful fallback on non-Samsung)

C) Samsung-first — use DeX/Flow/Knox aggressively for the best possible experience on your hardware, portability is not a concern

X) Other (please describe after [Answer]: tag below)

[Answer]: A — stay generic Android (public APIs only). Prefer portability; no Samsung-specific dependencies.

---

## Question 6 — Messages & notifications: how interactive on the Mac?
Read-only mirror, or full two-way control?

A) Read-only — see notifications and incoming SMS on the Mac, but reply/dismiss happens on the phone

B) Two-way for messages — read and **reply** to SMS from the Mac; notifications are read-only

C) Fully interactive — reply to SMS, and dismiss/act on notifications (including quick-reply to apps like WhatsApp) from the Mac

X) Other (please describe after [Answer]: tag below)

[Answer]: A-ish — "one way is fine, keep the options open." INTERPRETATION (flag if wrong): notifications are read-only mirror in v1; SMS is two-way (send + receive from the Mac) because SMS send is a named core feature in Q3. Architecture keeps two-way notification quick-reply open for a later milestone.

---

## Question 7 — Minimum Android version
What's the oldest Android we must support? (Affects which APIs are available.)

A) Android 14+ (newest only — cleanest APIs, matches a recent Galaxy)

B) Android 13+ (one version of headroom)

C) Android 11+ (broad compatibility, more legacy handling)

X) Other (please describe after [Answer]: tag below)

[Answer]: B — Android 13+ (developed/tested on the user's Android 16 device).

---

## Question 8 — Pairing & security model
How do the two devices establish trust on first connection?

A) QR-code pairing + per-device TLS certificates, trust pinned on first pair (local, no accounts — the KDE Connect model)

B) QR/PIN pairing + a shared key, encrypted local link (simpler than full mTLS)

C) Account-based login on both devices (needed if you ever want remote/cloud relay — see Q2)

X) Other (please describe after [Answer]: tag below)

[Answer]: A — QR-code pairing + per-device TLS certificates, trust-on-first-pair, fully local, no accounts.

---

## Question 9 — Mac app technology
You chose "native Mac polish." Confirm the stack for the Mac side.

A) SwiftUI menu-bar + windowed app (native, modern, best polish on Apple Silicon) — recommended

B) AppKit (more control, more code, older-style APIs)

C) Cross-platform (Electron/Tauri/Flutter) — faster to build but not truly "native polish"

X) Other (please describe after [Answer]: tag below)

[Answer]: A — SwiftUI menu-bar + windowed app (AppKit interop where required).

---

## Question 10 — Android app technology
Confirm the stack for the phone side.

A) Kotlin + Jetpack Compose, foreground service for the device link — recommended

B) Kotlin with classic Views/XML

C) Cross-platform (Flutter/React Native) — note: deep system access (SMS, notifications, screen capture) still needs native modules

X) Other (please describe after [Answer]: tag below)

[Answer]: A — Kotlin + Jetpack Compose, foreground service for the device link.

---

# Extension opt-ins (AI-DLC)

These configure how strictly the workflow enforces certain engineering practices.

## Question 11 — Security Extensions
Should security extension rules be enforced for this project?

A) Yes — enforce all SECURITY rules as blocking constraints (recommended for production-grade applications)

B) No — skip all SECURITY rules (suitable for PoCs, prototypes, and experimental projects)

X) Other (please describe after [Answer]: tag below)

[Answer]: A — enforce SECURITY rules. Private data, must not leak; testing is critical.

## Question 12 — Resiliency Extensions
Should the resiliency baseline be applied to this project? (Directional best practices from the AWS Well-Architected Reliability Pillar — a starting point, not a production guarantee.)

A) Yes — apply the resiliency baseline as design-time guidance (recommended for business-critical workloads)

B) No — skip the resiliency baseline (suitable for PoCs, prototypes, experimental projects)

X) Other (please describe after [Answer]: tag below)

[Answer]: B — skip the resiliency baseline (local P2P app, not a cloud workload; normal reconnect/retry handled as ordinary engineering).

## Question 13 — Property-Based Testing Extension
Should property-based testing (PBT) rules be enforced for this project?

A) Yes — enforce all PBT rules as blocking constraints (recommended for projects with business logic, data transformations, serialization, or stateful components)

B) Partial — enforce PBT rules only for pure functions and serialization round-trips

C) No — skip all PBT rules (suitable for simple CRUD/UI-only projects)

X) Other (please describe after [Answer]: tag below)

[Answer]: B — Partial PBT (pure functions + serialization round-trips). Enforced rules: PBT-02, PBT-03, PBT-07, PBT-08, PBT-09.

---

# Recorded Answers (summary)

| Q | Topic | Decision |
|---|---|---|
| 1 | Audience | Personal + open-source; no store/release work in v1 |
| 2 | Connectivity | Local Wi-Fi/LAN P2P for data + screen; Bluetooth HFP for call audio |
| 3 | MVP scope | All features **except screen control** (view-only mirroring in v1) |
| 4 | Calls | Accept Bluetooth HFP audio + on-Mac caller-ID/controls; seamless |
| 5 | Samsung APIs | Generic Android only (no Samsung-specific deps) |
| 6 | Interactivity | Notifications read-only; SMS two-way; quick-reply open for later |
| 7 | Min Android | Android 13+ |
| 8 | Pairing/security | QR + per-device TLS, trust-on-first-pair, no accounts |
| 9 | Mac stack | SwiftUI menu-bar + windowed |
| 10 | Android stack | Kotlin + Jetpack Compose, foreground service |
| 11 | Security ext | **Enabled** (blocking) |
| 12 | Resiliency ext | **Disabled** |
| 13 | PBT ext | **Partial** (pure functions + serialization round-trips) |
