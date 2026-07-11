# AI-DLC State

## Project
- **Name**: android_bridge
- **Description**: All-in-one continuity hub between Samsung Galaxy (Android) and Mac (Apple Silicon) — SMS/messages, notifications, file drag-and-drop, clipboard, screen mirroring/control, and phone calls — the Android↔Mac equivalent of Apple Continuity.
- **Workspace Root**: /Users/iliagerman/Work/personal_projects/android_bridge

## Workspace State
- **Existing Code**: Yes — native Android app, native macOS app, and shared protocol implementations exist.
- **Programming Languages**: Kotlin, Swift
- **Build System**: Gradle (Android/Kotlin), SwiftPM (macOS/Swift)
- **Project Structure**: Monorepo with `android/`, `mac/`, `protocol/`, and `aidlc-docs/`.
- **Brownfield**: true for future increments
- **Reverse Engineering Needed**: No — current architecture and implementation state are documented in this AI-DLC record.

## Known Constraints (from research)
- Phone-call audio on Android cannot be relayed over Wi-Fi by a third-party app (no API for live cellular call audio without root). Call audio path must be Bluetooth Hands-Free Profile (HFP); the app provides caller-ID + dial/answer control.
- RCS is locked to Google Messages; third-party apps get SMS/MMS via Telephony APIs only.
- Targets: Samsung Galaxy (Android) + Apple Silicon Mac (M1).
- Differentiators chosen by user: all-in-one unified hub, seamless calls, native Mac polish.
- Approach: build from scratch (not a KDE Connect fork).

## Extension Configuration
| Extension | Enabled | Decided At |
|---|---|---|
| Security Baseline | Yes | Requirements Analysis |
| Resiliency Baseline | No | Requirements Analysis |
| Property-Based Testing | Partial (pure functions + serialization round-trips: PBT-02, PBT-03, PBT-07, PBT-08, PBT-09) | Requirements Analysis |

## Stage Progress
### 🔵 INCEPTION PHASE
- [x] Workspace Detection
- [x] Reverse Engineering (SKIPPED — greenfield)
- [x] Requirements Analysis (approved)
- [x] User Stories (approved)
- [x] Workflow Planning (approved)
- [x] Application Design — **EXECUTE** (approved 2026-06-30)
- [x] Units Generation — **EXECUTE** (approved 2026-06-30; 12 units U1–U12)

### 🟢 CONSTRUCTION PHASE (per-unit loop, U1→U12)
**Per-unit stages**: Functional Design → NFR Requirements → NFR Design → (Infra Design SKIP) → Code Generation.
Executed autonomously (user away; recommended defaults taken). Approval gates recorded in audit.md.

**Legend** — ✅ done & verified · ◐ logic implemented + unit-tested, device-hardware parts not hardware-verified in this env · ⬜ pending.

| Unit | Func Design | NFR Req | NFR Design | Code Gen |
|------|:----------:|:-------:|:----------:|:--------:|
| U1 Protocol/Transport | ✅ | ✅ | ✅ | ✅ (Kotlin+Swift, PBT green, interop) |
| U2 Pairing & Security | ✅ | ✅ | ✅ | ✅ (both langs, unit-tested) |
| U3 Discovery & Connection | ✅ | ✅ | ✅ | ◐ (state machine + NSD wrapper; full mTLS transport not hw-verified) |
| U4 Notifications | ✅ | ✅ | ✅ | ◐ (listener + mapper; not hw-verified) |
| U5 SMS | ✅ | ✅ | ✅ | ◐ (mapper; Telephony read not hw-verified) |
| U6 File Transfer | ✅ | ✅ | ✅ | ◐ (chunk/reassemble tested; transport not hw-verified) |
| U7 Clipboard | ✅ | ✅ | ✅ | ✅ (sync policy, both langs, tested) |
| U8 Screen Mirror | ✅ | ✅ | ✅ | ◐ (framing tested; MediaProjection capture not hw-verified) |
| U9 Calls | ✅ | ✅ | ✅ | ◐ (mappers tested; InCallService/HFP not hw-verified) |
| U10 Settings & Permissions | ✅ | ✅ | ✅ | ✅ (registry/toggles, both langs, tested) |
| U11 Mac Shell | ✅ | ✅ | ✅ | ✅ (SwiftUI compiles+links; .app bundle needs Xcode) |
| U12 Android Shell | ✅ | ✅ | ✅ | ✅ (Compose UI; debug APK builds) |

- [x] Infrastructure Design — **SKIPPED** (no cloud/server infra)
- [x] Build & Test — instructions in `aidlc-docs/construction/build-and-test/`; suites run green (see Build Status below)

### 🟡 OPERATIONS PHASE
- [ ] Operations (placeholder)

### 🔁 POST-CONSTRUCTION FEATURE INCREMENTS
- [x] Increment 6: Continuous installation artifacts — every push to `main` builds and publishes a rolling `latest-build` prerelease containing the macOS archive, debug-signed Android APK, and SHA-256 checksums. Public `install.sh` always installs the newest Mac build; README links the APK directly. Shell/YAML/macOS packaging/Android APK/checksum validation green.
- [x] Call-control compatibility fix — Mac now sends protocol-aligned `answer`/`decline`; Android accepts both new names and legacy aliases, and dialing is centralized through `dialFromMac(...)`.
- [ ] Increment 1: Call control hardening — permission/status reporting, call-action result feedback to Mac, active call state updates, target Samsung hardware verification.
- [x] Increment 2: Bluetooth HFP feasibility spike — **COMPLETE, hardware-validated on S23 Ultra + M1 Mac**. **Verdict: call audio over HFP does NOT work on this hardware.** HFP *control* works (Mac connects as HF, `call active = 1`) but the *SCO audio* link fails to establish (`BTM_CreateSco Fail` / `HFSCO-SCO fail reason 13`) — audio stays on the phone. Root cause: macOS/controller-level SCO limitation as HFP Hands-Free unit; not fixable from the app. Decision: **do NOT build Option C (HfpAudioBridge); ship the manual-audio fallback** — Wi-Fi/TLS keeps full call control (built), call audio stays on the phone or a phone-paired BT headset, with clear UI copy. Probe kept for future OS re-test. Findings: `aidlc-docs/increments/increment-2-hfp-feasibility.md`.
- [ ] Increment 3: Native call UX polish — in-call panel, setup checklist, call history/contact polish, Bluetooth route guidance.
- [x] Increment 4: Meeting capture — Android voice recording + photos, one-minute AMR-WB chunk transfer, Mac local meeting workspace, project-local Whisper wrapper, Ollama/Gemma summary fallback, timestamped Markdown notes, and meetings-folder UI. Implemented and build/test green. Summary: `aidlc-docs/construction/meeting-capture-code-summary.md`.
- [x] Increment 5: Meetings rename + Second Brain tab — renamed the Mac Notes UI to Meetings, added a Second Brain tab mapped to `BRAIN_ROOT`/`~/second_brain`, supports browse/read/search/edit/create/delete/chat on selected nodes, and added per-task LLM routing for summarize, chat, second-brain search/Q&A/CRUD with local Ollama default and optional pi model selection. pi calls load only the second-brain skill.

**Post-construction plan**: `aidlc-docs/NEXT-FEATURE-IMPLEMENTATION.md`

## Build & Test Status (updated 2026-07-05 after call-control fix)
| Target | Command | Result |
|--------|---------|--------|
| Protocol (Kotlin) | `./gradlew :protocol:test` | ✅ Kotest PBT + cross-language interop |
| Protocol (Swift) | `swift test` (XCTest + SwiftCheck) | ✅ 8 tests, 3×100 SwiftCheck cases |
| Protocol (Swift, Xcode-free) | `swift run ProtocolCheck` | ✅ 9 checks (kept as smoke runner) |
| Android unit tests | `./gradlew :app:testDebugUnitTest --no-daemon` | ✅ 24 tests incl. mTLS loopback integration; re-run after call-control fix |
| Android APK | `./gradlew :app:assembleDebug` | ✅ app-debug.apk (~32 MB, w/ BouncyCastle) |
| Android app on emulator | `adb install` + launch | ✅ installs, launches, UI renders (screenshot) |
| Mac core (Xcode-free) | `swift run MacCheck` | ✅ 13 checks |
| Mac tests | `swift test` (XCTest + SwiftCheck) | ✅ 11 tests + 100 SwiftCheck cases; re-run after call-control fix |
| macOS .app | `mac/scripts/make-macos-app.sh` | ✅ AndroidBridge.app builds, launches, quits cleanly |

**Toolchain**: Android SDK platform-34 + build-tools 34.0.0; Gradle 8.10.2 (wrapper) on JDK 23; emulator
`system-images;android-34;google_apis;arm64-v8a` (AVD `bridge34`). **Xcode 26.6** installed → Swift now uses
XCTest + SwiftCheck (the NFR-specified PBT framework) and a runnable macOS `.app` is produced. The
dependency-free `ProtocolCheck`/`MacCheck` executables are kept as Xcode-free smoke runners.
**Verified in-process**: real mutual-TLS handshake + pinned-peer rejection (`TlsIntegrationTest`).
**Still not hardware-verified** (needs a real phone + second device): live LAN link, NSD discovery,
notification/SMS/telephony capture, screen capture, Mac-initiated cellular dialing on target Samsung, incoming-call answer/decline from Mac, Bluetooth HFP audio.

## Execution Plan Summary
- **Stages executed**: Application Design, Units Generation, per-unit construction (Func/NFR/NFR-Design/Code) for U1–U12, Build & Test.
- **Stages skipped**: Reverse Engineering (greenfield), Infrastructure Design (local P2P, no cloud).
- **Plan doc**: `aidlc-docs/inception/plans/execution-plan.md`
