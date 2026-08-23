# Build & Test Summary — android_bridge

Consolidated view of how to build/test the monorepo and what is verified. Companion files:
`build-instructions.md`, `unit-test-instructions.md`, `integration-test-instructions.md`,
`performance-test-instructions.md`.

---

## Quick commands
| Goal | Command |
|------|---------|
| Build + test Kotlin protocol | `cd android && ./gradlew :protocol:test` |
| Build + test Swift protocol | `cd protocol/swift && swift test` (or `swift run ProtocolCheck`) |
| Android unit tests | `cd android && ./gradlew :app:testDebugUnitTest` |
| Android debug APK | `cd android && ./gradlew :app:assembleDebug` |
| Run app on emulator | `adb install -r app/build/outputs/apk/debug/app-debug.apk` |
| Build + test Mac | `cd mac && swift test` (or `swift run MacCheck`) |
| Build runnable macOS .app | `mac/scripts/make-macos-app.sh` → `open mac/dist/AndroidBridge.app` |

## Verified-today matrix (autonomous run, 2026-07-01; updated after Xcode 26.6 install)
| Part | Builds | Tests | Notes |
|------|:------:|:-----:|-------|
| `protocol/kotlin` (U1) | ✅ | ✅ | Kotest PBT-02/-03 + examples + interop |
| `protocol/swift` (U1) | ✅ | ✅ | `swift test`: 8 XCTest + 3×100 SwiftCheck; `ProtocolCheck` fallback |
| Cross-language interop | — | ✅ | both decode `protocol/vectors/control-messages.jsonl` |
| `android/` app | ✅ | ✅ | **APK ~32 MB**; **24 unit tests** incl. in-process mTLS; installs+launches on emulator |
| `mac/` app + core | ✅ | ✅ | `swift test`: 10 tests + SwiftCheck; runnable **AndroidBridge.app** built + launches |

## Environment constraints (carry into any claim of "tested")
- **Xcode 26.6 installed** → Swift uses **XCTest + SwiftCheck** (`swift test`) as the primary path; the
  dependency-free harness (`ProtocolCheck`/`MacCheck` + `PropertyHarness.swift`) is kept as an Xcode-free
  fallback. A runnable macOS `.app` **is** produced (`mac/scripts/make-macos-app.sh`; ad-hoc signed, not notarized).
- **No phone / no second device** → the live cross-device link, telephony, screen-capture, Bluetooth-HFP, and
  NSD discovery are **not hardware-verified**. Their logic (protocol, routing, pairing, chunking, mappers,
  state machines) **is** unit-tested, and the **mTLS handshake + pinning is verified in-process**
  (`TlsIntegrationTest`). See `integration-test-instructions.md` for the manual two-device procedure.

## Compliance at Build & Test
- **PBT (Partial: PBT-02/-03/-07/-08/-09):** satisfied for U1 in both languages; pure feature/core logic
  (chunking, router, pairing) covered by property + example tests. Seeds logged on failure.
- **SECURITY-10 (supply chain):** versions pinned (`Package.resolved`; pinned Gradle coordinates). Remaining
  at release: Gradle dependency lockfile + version catalog, CI vulnerability scan, SBOM, no `latest` tags.
- **SECURITY-03 (no-PII logs):** `LinkLogger` redacts a forbidden field set and is unit-tested (`LinkLoggerTest`).

## Honest overall status
**U1 is built and tested in both languages (Kotest / XCTest+SwiftCheck) with cross-language interop. The
Android app builds an installable debug APK (~32 MB), passes 24 unit tests including an in-process mTLS
integration test, and installs + launches on an emulator. The Mac app (SwiftUI) and shared core pass
`swift test`, and a runnable `AndroidBridge.app` is produced and launches.** Beyond that, the live
cross-device features (real two-device mTLS link, NSD discovery, telephony/SMS/notification capture,
screen capture, Bluetooth HFP audio) are implemented against real OS APIs but **not hardware-verified** —
they need an Android 13+ phone + a Mac on the same LAN to complete end-to-end verification using the
integration instructions.

---

## File Notification Copy Bug — 2026-08-14
- **Source**: `mac/Sources/BridgeApp/main.swift`
- **Behavior**: File-toast Copy now uses received-file `path` metadata; other toasts still copy their body.
- **Unit/property tests**: `cd mac && swift test` passed 25 XCTest cases plus 100 SwiftCheck cases.
- **Build**: `cd mac && swift build` passed.
- **Deployment**: Release app built with `android-bridge`, installed to `/Applications/AndroidBridge.app`, and relaunched successfully.
- **Artifact identity**: Built and installed executable SHA-256 values match.
- **Manual hardware check**: Send another file from the phone and click Copy; the pasteboard should contain `/Users/iliagerman/Library/Caches/AndroidBridge/Received/<filename>`.
- **Known packaging warning**: Strict code-sign verification reports the pre-existing absolute Python symlink inside the bundled MLX Whisper virtual environment. App launch and this bug fix are unaffected.

---

## Meeting Completion and Calendar Enrichment — 2026-08-17

- **Unit**: `MCAL1-meeting-calendar-experience`.
- **Tests**: `cd mac && swift test` passed 30 XCTest cases; calendar and stream SwiftCheck properties each passed 100 generated cases.
- **Smoke checks**: `cd mac && swift run MacCheck` passed 14/14.
- **Build**: `cd mac && swift build` and release app assembly passed.
- **Static validation**: `git diff --check`, shell syntax, and installed plist validation passed.
- **Deployment**: Signed with `android-bridge`, installed to `/Applications/AndroidBridge.app`, and relaunched.
- **Artifact identity**: Built and installed executable SHA-256 values match: `d9e481db18152be1ad5f897f363559477466adb5be5c841d7dce2445725ee146`.
- **Calendar integration**: Installed Info.plist contains `NSCalendarsUsageDescription` and `NSCalendarsFullAccessUsageDescription`.
- **Calendar validation**: Real EventKit matching returned three candidate events. Calendar TCC was reset; the installed app proactively requested access and TCC logged a prompt plus registration creation for `com.androidbridge.mac`.

---

## Meeting Processing Recovery — 2026-08-17

- **Root cause**: `zai/glm-5.2` returned HTTP 429 quota exhausted; the optional LLM result was silently treated as successful completion.
- **Data finding**: Reported transcripts were present on disk; only summaries were missing.
- **Fix**: Failed summaries now produce `Needs Attention`; UI distinguishes missing summary from missing transcript and provides explicit retry; Calendar access is requested and reported explicitly.
- **Provider correction**: Summarize changed to verified `openai-codex/gpt-5.6-sol`.
- **Recovery**: 68/68 transcript-bearing meetings now have the preferred English/Detailed summary. All four affected August 17 meetings are backfilled and `Ready`.
- **Tests**: `swift test` passed 31 XCTest cases plus two SwiftCheck properties at 100 cases each; MacCheck passed 14/14.
- **Deployment**: Signed, installed to `/Applications/AndroidBridge.app`, relaunched, and verified running.
- **Artifact identity**: Built/installed SHA-256 values matched for that deployment: `32209cd933b0086347896b22abd7368a286030ffc0c04091c09a48cf68106f49`.

---

## macOS Permission Persistence — 2026-08-17

- **Root cause**: Packaging chose the first keychain identity and suppressed signing failures; TCC grants require a stable designated code requirement. Screen Recording also retained a stale row, while Calendar had been explicitly reset during incident recovery.
- **Fix**: Packaging pins fingerprint `A0B15CA62926F788FFFC550CA7A7737AA64C7699`, aborts on signing failure or requirement drift, stages/verifies before replacement, and verifies after installation.
- **App behavior**: Added explicit Screen Recording request; when access is off, launch requests it and explains that a relaunch is required.
- **Update validation**: Repeated installs retained `identifier "com.androidbridge.mac" and certificate leaf = H"a0b15ca62926f788fffc550ca7a7737aa64c7699"`.
- **Calendar validation**: Zero Calendar prompts or TCC row changes occurred across repeated unchanged-identity updates.
- **Tests**: 31 XCTest cases plus two SwiftCheck properties at 100 cases each passed; MacCheck passed 14/14; release signature verification passed.
- **One-time manual action**: Enable Android Bridge in Screen Recording and relaunch. macOS does not permit self-granting this permission.

---

## Clipboard and Second Brain reliability — 2026-08-22

- **Android tests:** 46 passed; Android protocol tests passed.
- **Android build:** debug APK built at `android/app/build/outputs/apk/debug/app-debug.apk`.
- **Android APK SHA-256:** `473ade92019f8c8e00aecb4db0ebefbcdc2cd6be09ed9243209f987aeceef409`.
- **Mac tests:** 33 XCTest passed plus two 100-case SwiftCheck properties.
- **Mac smoke:** MacCheck passed 14/14; Swift build passed.
- **Swift protocol:** 8 XCTest, SwiftCheck properties, and ProtocolCheck 9/9 passed.
- **Static checks:** `git diff --check`, Markdown/content validation, privacy-log search, and temporary-debug-marker search passed.
- **Deployment:** signed Mac app installed and relaunched with unchanged designated requirement.
- **Mac artifact identity:** built and installed executable SHA-256 values match `3f68f2d7714325217ce554ea1a64702b98726e405a676d600d953e5f771bfc15`.
- **Android deployment:** APK installed with `adb install -r` on Pixel 9a `62051JEBF07522`; app relaunched and no recent AndroidRuntime crash was present.
- **Pending:** live two-device clipboard and Second Brain verification.

---

## Meeting customer automation — 2026-08-22

- **Behavior:** searchable customer catalog/create flow, remembered calendar associations, preferred calendar, 15-minute event tolerance, ambiguity prompts, and association correction.
- **Mac tests:** 40 XCTest passed plus three 100-case SwiftCheck properties.
- **Mac smoke:** MacCheck passed 14/14; Swift build passed.
- **Static checks:** `git diff --check`, privacy-log search, and temporary-debug-marker search passed.
- **Dependencies/protocol:** unchanged.
- **Deployment:** signed app installed and relaunched with unchanged designated requirement.
- **Artifact identity:** built and installed executable SHA-256 values match `e9ceae282110bd4bfa4e2ee073514e66a57ce67c5a5eb66b67aeef81e43ebfc1`.
- **Packaging warning:** strict verification still reports the pre-existing absolute Python symlink in the bundled Whisper environment; plain code-sign verification and the packaging script pass.
- **Manual verification:** use section 6 of `integration-test-instructions.md`.

---

## Direct distribution packaging and trusted updates — 2026-08-23

- **Release tooling:** 7 Python tests, shell syntax, Ruby YAML parse, actionlint, and workflow policy passed.
- **Android:** updater tests and full debug suite passed; debug APK assembled; release APK assembled with the dedicated long-lived key and apksigner v2 verification passed.
- **Android release signer SHA-256:** `108b8f8ac860041b0845c9c426cfe7125c8e99899cde031791359a180f233410`.
- **Mac:** 51 XCTest tests passed, including 11 updater tests, plus existing property checks; Swift build passed.
- **Mac package:** distribution identity requirement matched; app signature passed; read-only UDZO DMG built, mounted, copied-app verified, and detached.
- **Integrated contract:** local versioned DMG/APK, stable aliases, checksums, two CycloneDX-shaped SBOM fixtures, and schema-1 manifest formed an 11-file set accepted by `scripts/release.py validate`.
- **Secrets:** six required GitHub Actions secret names are configured. The Android keystore remains outside Git with passwords in macOS Keychain.
- **Local deployment:** Mac app rebuilt, installed with unchanged local identity, and relaunched. Android was correctly skipped when no authorized device remained connected.
- **Remaining external evidence:** GitHub Actions Syft/Grype execution, rolling promotion, stable Release publication, clean-machine DMG install, and physical same-key Android upgrade.
