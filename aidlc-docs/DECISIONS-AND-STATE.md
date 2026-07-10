# android_bridge — Decisions, State & Open Questions

> One place for **every decision made so far**, **where we are in the workflow**, and **open
> questions you can answer inline** (fill the `[Answer]:` lines, then tell me "I updated the doc"
> or just reply in chat). Last updated: 2026-07-05.

---

## Part 1 — Project snapshot

- **What**: Local-only, peer-to-peer continuity hub between a **Mac (Apple Silicon, SwiftUI)** and
  an **Android phone (13+, Kotlin/Compose)** — the Android↔Mac answer to Apple Continuity.
- **v1 features**: notification mirroring · SMS/MMS mirroring · file drag-and-drop · clipboard sync ·
  screen mirroring (view-only) · phone-call control (caller-ID, answer/decline/dial, history).
- **Link**: one mutual-TLS session over the LAN carrying length-prefixed JSON control + binary frames.
  Call **audio** rides Bluetooth HFP (OS-level), never the protocol.

---

## Part 2 — All decisions (locked)

### A. Product & scope
| # | Decision |
|---|----------|
| P1 | Local-only, peer-to-peer, **no servers / no cloud / no accounts** |
| P2 | Call **audio via Bluetooth HFP** (Android has no API for live cellular call audio); only call control/metadata over the link |
| P3 | **Generic Android public APIs only** — no DeX/Flow/Knox; portable to any Android 13+ |
| P4 | **SMS read-only in v1** (receive + history on Mac; send deferred) |
| P5 | **Notifications read-only in v1** (mirror to Mac; actions/quick-reply deferred) |
| P6 | **Screen mirroring view-only in v1** (tap/type-back control deferred) |
| P7 | Open-source-ready, single primary user; no app-store/notarization in v1 |
| P8 | Deferred ([Later]): US-3.3 notification actions · US-4.3 SMS send · US-7.3 screen control |

### B. Architecture (Application Design Q1–Q4)
| # | Decision |
|---|----------|
| AR1 | **Single mTLS session, multiplexed** — typed JSON control + binary frames for bulk (Q1) |
| AR2 | **One hand-written schema, length-prefixed JSON**, implemented per language (Q2) |
| AR3 | **Feature-plugin modules on a shared Core** on both apps (Q3) |
| AR4 | **mDNS / Bonjour** discovery — `NWBrowser` (Mac) / `NsdManager` (Android) (Q4) |
| AR5 | QR pairing + per-device **mTLS with pinned certs** (trust-on-first-use) |
| AR6 | Encrypted at rest — Keychain (Mac) / Keystore + EncryptedSharedPreferences (Android) |
| AR7 | Acyclic layering: UI → Services → Plugins → Core → Protocol/mTLS |

### C. Decomposition (Units Generation Q1–Q5)
| # | Decision |
|---|----------|
| U-Q1 | **7 separate feature units** (don't merge small ones) |
| U-Q2 | **Single monorepo**: `mac/` + `android/` + `protocol/` |
| U-Q3 | U1 deliverable = `protocol/PROTOCOL.md` spec + Swift + Kotlin impls + round-trip PBT |
| U-Q4 | **Walking skeleton first** (pair + connect + 1 round-trip msg) after U1–U3, before features |
| U-Q5 | **Clipboard default = manual push** (auto-sync is opt-in) — *resolves the one requirements open item* |

**12 units, build order**: U1 Protocol → U2 Pairing & Security → U3 Discovery & Connection →
(U4 Notif · U5 SMS · U6 Files · U7 Clipboard · U8 Screen · U9 Calls · U10 Settings/Perms) →
U11 Mac shell + U12 Android shell.

### D. U1 Protocol wire contract (U1 Functional Design Q1–Q6)
| # | Decision |
|---|----------|
| D-Q1 | Control msg = **4-byte big-endian length prefix**, max **1 MiB** |
| D-Q2 | `protocolVersion` = **single integer** (v1=1); **reject connection on mismatch** |
| D-Q3 | **UUID `id`** per message + optional `replyTo` for correlation |
| D-Q4 | Binary frame header = `streamId(u32)·sequence(u32)·length(u32)·flags(u8)` (13 B); **64 KiB** chunk |
| D-Q5 | Malformed/unknown → **drop + log, keep link** (fail-closed); version mismatch → reject link |
| D-Q6 | Binary in JSON: **base64 inline ≤ 32 KiB**, larger → frame stream |

### E. U1 NFR & tooling (U1 NFR Requirements Q1–Q4)
| # | Decision |
|---|----------|
| E-Q1 | PBT: Swift → **SwiftCheck** · Kotlin → **Kotest Property Testing** (PBT-09) |
| E-Q2 | Test runner: Swift → **swift-testing** · Kotlin → **JUnit5 + Kotest** |
| E-Q3 | Codec perf target ≤~1 ms control / ≤~2 ms per 64 KiB frame (measured, not CI-gated) |
| E-Q4 | Dependency pinning (`Package.resolved` + Gradle catalog/lockfile); scan + SBOM at Build & Test |
| E-extra | JSON via native libs (Swift `Codable` / Kotlin `kotlinx.serialization`); no runtime 3rd-party codec deps |

### F. Extensions
| Extension | Status |
|-----------|--------|
| Security Baseline | **ON (blocking)** |
| Resiliency Baseline | OFF |
| Property-Based Testing | **PARTIAL** (PBT-02, -03, -07, -08, -09 enforced) |

---

## Part 3 — Current workflow state

| Phase | Stage | Status |
|-------|-------|--------|
| 🔵 Inception | Workspace Detection → Requirements → User Stories → Workflow Planning → Application Design → Units Generation | ✅ **all approved** |
| 🟢 Construction | U1–U12 Functional Design → NFR Requirements → NFR Design → Code Generation | ✅ **complete** |
| | Infrastructure Design | ⏭️ skipped (no cloud/server infra) |
| | Build & Test | ✅ complete; latest Android and Mac tests passed 2026-07-05 |
| 🟡 Operations | Operations | ⬜ placeholder |
| 🔁 Post-construction increments | Call-control compatibility fix | ✅ complete |
| | Call control hardening | ⬜ next |
| | Bluetooth HFP feasibility spike | ⬜ next major feature investigation |
| | Native call UX polish | ⬜ after HFP feasibility |

The repo now contains application code in `android/`, `mac/`, and `protocol/`. The original greenfield construction loop is complete; future work should be tracked as focused post-construction feature increments.

Latest call-control implementation update:

- Mac sends protocol-aligned `call.action` values: `answer`, `decline`, `dial`.
- Android accepts `answer`/`accept`, `decline`/`hangup`, and `dial`.
- Android dialing is centralized through `TelecomManager.placeCall(...)` with a legacy `ACTION_CALL` fallback.
- Validation passed: Android unit tests and Mac Swift tests.

---

## Part 4 — NEXT FEATURE IMPLEMENTATION

See `aidlc-docs/NEXT-FEATURE-IMPLEMENTATION.md`.

Priority order:

1. Call control hardening and real-device verification.
2. Bluetooth HFP feasibility spike for cellular call audio through Mac mic/speakers.
3. Native call UX polish around active call state, setup guidance, and history/contact display.

---

## Part 5 — Source artifacts
- Requirements: `aidlc-docs/inception/requirements/requirements.md`
- App design: `aidlc-docs/inception/application-design/` (incl. `unit-of-work*.md`)
- Feature implementation plan: `aidlc-docs/NEXT-FEATURE-IMPLEMENTATION.md`
- Plans (with recorded answers): `aidlc-docs/inception/plans/`, `aidlc-docs/construction/plans/`
- State / audit: `aidlc-docs/aidlc-state.md`, `aidlc-docs/audit.md`
- Narrative recap: `aidlc-docs/DESIGN-RECAP.md`
