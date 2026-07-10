# User Stories — android_bridge

**Format**: Feature-based epics · INVEST stories · Given/When/Then acceptance criteria · scope tags **[v1]** / **[Later]**.
**Personas**: P1 = Owner-User, P2 = Open-Source Contributor (see `personas.md`).
**Source**: `requirements.md` (FR-1..FR-9, NFR-1..NFR-7).

**Cross-cutting acceptance criteria (apply to every story that moves data over the link):**
- **CC-SEC**: All device-to-device traffic flows only over the **mutually-authenticated TLS** link; an unpaired/unpinned peer is rejected. *(NFR-2 / SECURITY-06, -08)*
- **CC-PRIV**: No message bodies, phone numbers, contacts, or tokens appear in logs. *(SECURITY-03)*
- **CC-VALID**: Every inbound wire message is validated (type, size, format) and **safely deserialized** before use; malformed messages are dropped, not crashed on. *(SECURITY-05, -13, -15 fail-closed)*

---

## Epic E1 — Pairing & Trust

### US-1.1 — Pair via QR code **[v1]**
As **P1**, I want to pair my Mac and phone by scanning a QR code on the same network, so that the two devices trust each other without any account.
- **Given** both apps are open on the same LAN and unpaired, **When** I display the QR on one device and scan/enter it on the other, **Then** the devices complete pairing and show "Paired".
- **Given** pairing completes, **When** it finishes, **Then** each device has generated its own TLS keypair and **pinned** the peer's certificate (trust-on-first-use), with no cloud/account involved. *(FR-1.1–1.3)*
- **Given** a third device tries to connect, **When** it is not pinned, **Then** the connection is refused. *(CC-SEC)*

### US-1.2 — Store pairing secrets securely **[v1]**
As **P1**, I want pairing keys kept in secure OS storage, so that my trust material can't be trivially read off disk.
- **Given** pairing has completed, **When** keys/certs are persisted, **Then** they are stored in **macOS Keychain** / **Android Keystore (or EncryptedSharedPreferences)**, never in plaintext files. *(FR-1.5 / SECURITY-01, -12)*

### US-1.3 — View and unpair devices **[v1]**
As **P1**, I want to see paired devices and remove one, so that I can revoke trust when I stop using a device.
- **Given** at least one paired device, **When** I open the devices list, **Then** I see each paired device with name and status.
- **Given** I choose "Unpair", **When** I confirm, **Then** the peer's pinned trust is deleted and that device can no longer connect until re-paired. *(FR-1.4)*

---

## Epic E2 — Discovery & Connection

### US-2.1 — Auto-discover the paired device on the LAN **[v1]**
As **P1**, I want my devices to find each other automatically, so that I never type IP addresses.
- **Given** both paired devices are on the same network, **When** both apps are running, **Then** they discover each other (mDNS/Bonjour or broadcast) and establish the mTLS link automatically. *(FR-2.1)*

### US-2.2 — Keep the link alive in the background (Android) **[v1]**
As **P1**, I want the phone to maintain the connection in the background, so that continuity works without keeping the app open.
- **Given** the Android app is backgrounded, **When** the device is on, **Then** a **foreground service** keeps the link alive and shows an ongoing status notification. *(FR-2.2)*

### US-2.3 — See connection status **[v1]**
As **P1**, I want clear connection status on both devices, so that I know whether continuity is active.
- **Given** the apps are running, **When** the link state changes, **Then** the Mac menu-bar and the Android app show connected / reconnecting / disconnected. *(FR-2.3)*

### US-2.4 — Auto-reconnect after a network drop **[v1]**
As **P1**, I want the link to recover by itself after a Wi-Fi blip, so that I don't have to re-pair or restart.
- **Given** the link drops due to transient network loss, **When** both devices are reachable again, **Then** the connection re-establishes automatically without re-pairing. *(FR-2.4 / NFR-5.1)*

---

## Epic E3 — Notification Mirroring (read-only in v1)

### US-3.1 — See phone notifications on the Mac **[v1]**
As **P1**, I want my Android notifications mirrored to the Mac, so that I don't reach for my phone.
- **Given** notification access is granted on Android, **When** a notification arrives, **Then** it appears on the Mac with app name, title, text, icon, and timestamp as a native macOS notification/feed. *(FR-3.1–3.2)*
- **Given** a notification is mirrored, **When** displayed, **Then** v1 provides **no dismiss/reply** action from the Mac. *(FR-3.3)*

### US-3.2 — Choose which apps mirror notifications **[v1]**
As **P1**, I want to control which apps mirror, so that noisy apps don't clutter my Mac.
- **Given** the notification settings, **When** I allow/deny specific apps, **Then** only allowed apps' notifications are mirrored, and the choice persists. *(FR-3.4, FR-9.3)*

### US-3.3 — Act on notifications from the Mac **[Later]**
As **P1**, I want to dismiss and quick-reply to notifications from the Mac, so that I can fully handle them at my desk.
- *(Deferred — architecture must leave the protocol/data model open for notification actions. FR-3.3 note.)*

---

## Epic E4 — SMS / MMS (read-only in v1)

### US-4.1 — Receive incoming SMS/MMS on the Mac **[v1]**
As **P1**, I want incoming texts to show on the Mac in real time, so that I see them while working.
- **Given** SMS permission is granted on Android, **When** an SMS/MMS arrives, **Then** it appears on the Mac with sender (contact name if resolvable), body, timestamp, and MMS attachments. *(FR-4.1)*

### US-4.2 — Read SMS conversation history on the Mac **[v1]**
As **P1**, I want to browse my text threads on the Mac, so that I have context for a conversation.
- **Given** I open Messages on the Mac, **When** I select a conversation, **Then** I see its message history grouped by thread. *(FR-4.2–4.3)*

### US-4.3 — Send SMS from the Mac **[Later]**
As **P1**, I want to reply to texts from the Mac, so that I never switch to the phone to respond.
- *(Deferred per approval — v1 is read-only. Data model/protocol must keep Mac-side send open. FR-4.4 note.)*

---

## Epic E5 — File Transfer

### US-5.1 — Drag a file from Mac to phone **[v1]**
As **P1**, I want to drag a file onto the Mac app to send it to my phone, so that transfers are effortless.
- **Given** a connected link, **When** I drop one or more files on the Mac app, **Then** they transfer over the LAN and land in the configured destination on the phone, showing progress and a success/failure result. *(FR-5.1–5.4)*

### US-5.2 — Send a file from phone to Mac **[v1]**
As **P1**, I want to send a file from the phone to the Mac, so that transfer works both ways.
- **Given** a connected link, **When** I share/select a file on Android to send, **Then** it transfers over the LAN to the Mac's configured destination with progress and a result. *(FR-5.1–5.3)*

### US-5.3 — Configure the received-files destination **[v1]**
As **P1**, I want to choose where received files are saved, so that they don't clutter a default folder.
- **Given** settings, **When** I set a destination folder per platform, **Then** received files are saved there and the setting persists. *(FR-5.3, FR-9.3)*

---

## Epic E6 — Clipboard Sync

### US-6.1 — Sync text clipboard between devices **[v1]**
As **P1**, I want clipboard text to move between devices, so that I can copy here and paste there.
- **Given** a connected link, **When** I copy text on one device and trigger sync (per the chosen default), **Then** the same text is available to paste on the other device, sent over the encrypted link. *(FR-6.1, FR-6.3 / CC-SEC)*

### US-6.2 — Control clipboard sync behavior **[v1]**
As **P1**, I want to choose auto-sync vs. manual push, so that my clipboard isn't shared unexpectedly.
- **Given** clipboard settings, **When** I pick auto-sync or manual push, **Then** the chosen behavior is applied and persists. *(FR-6.2)*
- *(Open item: which is the default — settled in design.)*

---

## Epic E7 — Screen Mirroring (view-only in v1)

### US-7.1 — View the phone screen on the Mac **[v1]**
As **P1**, I want to see a live mirror of my phone on the Mac, so that I can watch/monitor it without holding it.
- **Given** screen-capture permission is granted on Android, **When** I start mirroring, **Then** the Mac shows a live, low-latency H.264/H.265 stream of the phone screen over the LAN. *(FR-7.1–7.2)*
- **Given** mirroring is active, **When** it runs on a healthy 5 GHz LAN, **Then** end-to-end latency targets **≤ ~80 ms** with adaptive bitrate. *(NFR-3.1)*

### US-7.2 — Start/stop mirroring with a capture indicator **[v1]**
As **P1**, I want to start and stop mirroring and clearly see when capture is on, so that I stay in control of what's shared.
- **Given** a connected link, **When** I start or stop mirroring from either app, **Then** the stream starts/stops and the phone shows a clear "screen is being captured" indicator. *(FR-7.4)*

### US-7.3 — Control the phone from the Mac **[Later]**
As **P1**, I want to tap and type into the phone from the Mac, so that I can operate it fully from my desk.
- *(Deferred per approval — requires AccessibilityService or ADB-assisted input injection; to be scoped later. FR-7.3.)*

---

## Epic E8 — Phone Calls (controls on Mac, audio over Bluetooth)

### US-8.1 — One-time Bluetooth call setup during onboarding **[v1]**
As **P1**, I want guided one-time Bluetooth setup, so that call audio "just works" afterward.
- **Given** first-run onboarding, **When** I reach the calls step, **Then** the app guides me to pair the Mac as a Bluetooth Hands-Free device once, and confirms it's ready. *(FR-8.4–8.5, NFR-4.2)*

### US-8.2 — See caller-ID on the Mac for incoming calls **[v1]**
As **P1**, I want an incoming-call popup on the Mac, so that I know who's calling without looking at the phone.
- **Given** an incoming call and contacts access on Android, **When** the phone rings, **Then** the Mac shows a caller-ID popup with number, resolved contact name, and photo if available. *(FR-8.1, FR-8.7)*

### US-8.3 — Answer or decline a call from the Mac **[v1]**
As **P1**, I want to answer/decline from the Mac, so that I can take or dismiss calls at my desk.
- **Given** the caller-ID popup, **When** I click Answer or Decline, **Then** the phone performs that action and call audio routes via Bluetooth HFP. *(FR-8.2, FR-8.4)*

### US-8.4 — Place a call from the Mac **[v1]**
As **P1**, I want to dial or pick a contact on the Mac, so that I can start calls without the phone.
- **Given** a connected link, **When** I dial a number or choose a contact on the Mac, **Then** the phone initiates the call and audio routes via Bluetooth HFP. *(FR-8.3–8.4)*

### US-8.5 — View call history on the Mac **[v1]**
As **P1**, I want recent call history on the Mac, so that I can call back and review missed calls.
- **Given** a connected link, **When** I open call history, **Then** I see incoming/outgoing/missed calls with names/numbers and timestamps. *(FR-8.6)*

---

## Epic E9 — Settings & Permissions

### US-9.1 — Guided permission grants per platform **[v1]**
As **P1**, I want the app to explain and request the permissions it needs, so that setup is smooth and I understand why.
- **Given** first run or enabling a feature, **When** a permission is required (Android: notifications, SMS, contacts, screen capture, foreground service, Bluetooth; macOS: notifications, network, Bluetooth), **Then** the app explains why and routes me to grant it. *(FR-9.1)*

### US-9.2 — Enable/disable each feature independently **[v1]**
As **P1**, I want per-feature toggles, so that I run only the parts I want.
- **Given** settings, **When** I toggle a feature (notifications, SMS, files, clipboard, screen, calls), **Then** that feature activates/deactivates and the setting persists across restarts. *(FR-9.2–9.3)*

### US-9.3 — Graceful degradation when a permission is missing/revoked **[v1]**
As **P1**, I want the app to degrade gracefully if a permission is denied, so that one missing grant doesn't break everything.
- **Given** a feature's permission is denied or revoked, **When** I use the app, **Then** that feature is clearly shown as unavailable with a fix-it hint, and other features keep working (no crash). *(NFR-5.2 / SECURITY-15 fail-closed)*

---

## Epic E10 — Maintainability & Portability (Contributor)

### US-10.1 — Build and run both apps from a clean checkout **[v1]**
As **P2**, I want documented build/run steps, so that I can get the project running quickly.
- **Given** a fresh clone, **When** I follow the README/build instructions, **Then** I can build and run both the macOS and Android apps. *(NFR-6.3)*

### US-10.2 — Documented, separable device-link protocol **[v1]**
As **P2**, I want the wire protocol documented and isolated, so that I can add a feature without reworking transport.
- **Given** the codebase, **When** I read the protocol docs, **Then** message schemas and the transport layer are clearly defined and separated from feature code. *(NFR-6.2)*
- **Given** the protocol, **When** I inspect tests, **Then** each message type has a **round-trip property test** (`decode(encode(x)) == x`). *(NFR-7.2 / PBT-02)*

### US-10.3 — Runs on generic Android 13+ **[v1]**
As **P2**, I want no Samsung-specific dependencies, so that the app runs on other Android phones.
- **Given** any Android 13+ device, **When** I install and pair it, **Then** core features work using only public Android APIs (no DeX/Flow/Knox requirement). *(NFR-6.1, FR/Q5, Q7)*

---

## Scope Summary
| Tag | Stories |
|---|---|
| **[v1]** | US-1.1, US-1.2, US-1.3, US-2.1, US-2.2, US-2.3, US-2.4, US-3.1, US-3.2, US-4.1, US-4.2, US-5.1, US-5.2, US-5.3, US-6.1, US-6.2, US-7.1, US-7.2, US-8.1, US-8.2, US-8.3, US-8.4, US-8.5, US-9.1, US-9.2, US-9.3, US-10.1, US-10.2, US-10.3 |
| **[Later]** | US-3.3 (notification actions), US-4.3 (SMS send from Mac), US-7.3 (screen control) |

**INVEST check**: each story is independently buildable, negotiable, delivers user-visible value, is estimable at a few-days size, small, and has testable Given/When/Then criteria. Cross-cutting security/privacy/validation criteria (CC-SEC, CC-PRIV, CC-VALID) are attached as testable acceptance criteria rather than separate stories.
