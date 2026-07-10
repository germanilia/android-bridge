# Unit of Work Plan — android_bridge

Role: Software architect. This plan defines **how** we decompose the system into units of
work for construction. Detailed per-unit design happens later (Functional/NFR Design).

**Sources:** `requirements.md` · `user-stories/stories.md` (E1–E10) · `application-design/`.
**Locked context:** SwiftUI Mac · Kotlin/Compose Android · local mTLS over LAN · Bluetooth HFP
call audio · generic Android 13+ · Security ON · PBT partial · feature-plugin on shared Core.

**Action:** Answer **Q1–Q5** (fill the letter after each `[Answer]:`), then approve.
Generation of unit artifacts starts only after approval.

---

## Proposed Decomposition (default recommendation)

A "unit" here = a logical grouping of stories built together. These are **modules within two
apps + a shared protocol**, not deployable services (it's two native apps, not microservices).
Build order follows the dependency arrows: foundation first, feature units next, shells last.

| # | Unit | Stories | Depends on | Notes |
|---|------|---------|------------|-------|
| **U1** | **Protocol / Transport core** | US-10.2 | — | Message Envelope, Binary Frame, Type Registry; codecs (Swift + Kotlin). **Primary PBT-02 surface.** Foundation for everything. |
| **U2** | **Pairing & Security** | US-1.1–1.3 | U1 | PairingManager, SecureStore, mTLS identity, QR, cert pinning (Keychain/Keystore). |
| **U3** | **Discovery & Connection** | US-2.1–2.4, US-10.3 | U1, U2 | DeviceDiscovery (mDNS), ConnectionManager, MessageRouter, **Android LinkForegroundService**, auto-reconnect, state. |
| **U4** | **Notifications** | US-3.1–3.2 | U3 | NotificationListenerService → mirror; app allowlist. |
| **U5** | **SMS / MMS (read-only)** | US-4.1–4.2 | U3 | Telephony read + thread history. |
| **U6** | **File Transfer** | US-5.1–5.3 | U3 | Binary stream both directions, progress, destination. |
| **U7** | **Clipboard** | US-6.1–6.2 | U3 | Text sync, sync-mode setting. |
| **U8** | **Screen Mirror (view-only)** | US-7.1–7.2 | U3 | MediaProjection + MediaCodec encode → Mac decode/render; capture indicator. |
| **U9** | **Calls** | US-8.1–8.5 | U3 | Call state, contact resolve, answer/decline/dial, history, BT-HFP onboarding hint. |
| **U10** | **Settings & Permissions** | US-9.1–9.3 | U3 (light) | Per-feature toggles, permission prompts, graceful degradation. Cross-cuts all features. |
| **U11** | **Mac App Shell (SwiftUI)** | US-10.1 (Mac) | U2–U10 | Menu-bar + windows, onboarding, wiring of Core+plugins+services. |
| **U12** | **Android App Shell (Compose)** | US-10.1 (Android) | U2–U10 | Compose screens, onboarding, wiring; hosts the foreground service from U3. |

**Deferred ([Later]) stories** US-3.3, US-4.3, US-7.3 are **not** assigned to v1 units — the
protocol/plugin interfaces in U1/U4/U5/U8 are shaped to accept them without redesign.

---

## Recommended build order

```
U1 Protocol  →  U2 Pairing  →  U3 Discovery/Connection
                                      │
        ┌──────────────┬──────────────┼──────────────┬──────────────┐
       U4 Notif      U5 SMS        U6 Files       U7 Clip   U8 Screen   U9 Calls
        └──────────────┴──────────────┴──────────────┴──────────────┘
                                      │
                              U10 Settings/Perms (cross-cuts)
                                      │
                       U11 Mac shell  +  U12 Android shell  (integrate everything)
```

U1–U3 are the critical foundation. Feature units U4–U9 are independent of each other and
could be built in any order (or in parallel by different contributors).

---

## Mandatory artifacts (generated 2026-06-30)
- [x] `aidlc-docs/inception/application-design/unit-of-work.md` — unit definitions, responsibilities, code-organization strategy (greenfield)
- [x] `aidlc-docs/inception/application-design/unit-of-work-dependency.md` — dependency matrix
- [x] `aidlc-docs/inception/application-design/unit-of-work-story-map.md` — story → unit mapping
- [x] Validate unit boundaries; confirm every v1 story is assigned (29/29 v1 assigned; 3 [Later] intentionally open)

---

## Questions

### Q1 — Unit granularity
How fine-grained should the feature units be?
- **A) Keep all 7 feature units separate** (U4–U10) — recommended; cleanest boundaries, best for parallel/open-source work, matches the plugin architecture.
- B) Merge the small ones (Clipboard + Settings, maybe Notifications) into fewer units to reduce overhead.
- C) Go even finer (split Calls into "incoming/outgoing/history", split Files into send/receive).
- X) Other (describe)

[Answer]:

### Q2 — Code organization / repository layout (greenfield)
- **A) Single monorepo**, three top-level dirs: `mac/` (Swift/Xcode), `android/` (Kotlin/Gradle), `protocol/` (the shared spec + reference notes) — recommended; one clone, easy cross-device work, open-source friendly.
- B) Two separate repos (mac-app, android-app) with the protocol spec duplicated/vendored in each.
- C) Monorepo but protocol lives inside each app (no separate `protocol/` dir).
- X) Other (describe)

[Answer]:

### Q3 — Shared protocol unit deliverable (U1)
The protocol is hand-implemented per language (decided). What does U1 produce?
- **A) A language-neutral spec doc (`protocol/PROTOCOL.md`) + Swift impl + Kotlin impl together**, with the round-trip PBT in both languages — recommended; spec stays the single source of truth.
- B) Just the two language implementations; document inline in code, no separate spec doc.
- C) Spec doc first as its own mini-deliverable, implementations in a later pass.
- X) Other (describe)

[Answer]:

### Q4 — Integration strategy (how we prove it works end-to-end)
- **A) Walking skeleton first** — after U1–U3, build a thin end-to-end path (pair + connect + send one trivial round-trip message shown in both UIs) before fleshing out features — recommended; de-risks the hardest cross-device plumbing early.
- B) Complete each unit fully (incl. its UI) in isolation, integrate at the shells (U11/U12) at the end.
- C) Hybrid — walking skeleton, then complete units fully one at a time.
- X) Other (describe)

[Answer]:

### Q5 — Clipboard default (carried-over open item, FR-6.2 / US-6.2)
The one requirements open item: what is the **default** clipboard behavior?
- **A) Manual push by default** (copy stays local; user explicitly pushes) — recommended; safest/least-surprising, privacy-first, matches NFR-1 ethos. Auto-sync available as an opt-in setting.
- B) Auto-sync by default (every copy syncs both ways automatically), with a manual-only opt-out.
- C) Auto-sync one direction only by default (e.g., phone → Mac), manual the other way.
- X) Other (describe)

[Answer]:

---

## Recommendation in one line
Q1=A · Q2=A · Q3=A · Q4=A · Q5=A  (reply **"go"** to accept all).

---

## Answers (recorded 2026-06-30)
- **Q1 = A** — keep all 7 feature units separate (U4–U10).
- **Q2 = A** — single monorepo: `mac/` + `android/` + `protocol/`.
- **Q3 = A** — U1 produces `protocol/PROTOCOL.md` spec + Swift + Kotlin impls + round-trip PBT in both.
- **Q4 = A** — walking skeleton first (pair + connect + one round-trip message) after U1–U3, then flesh out features.
- **Q5 = A** — clipboard default = **manual push**; auto-sync is an opt-in setting.

(User response: "go" — accepted all recommendations. No ambiguities.)
