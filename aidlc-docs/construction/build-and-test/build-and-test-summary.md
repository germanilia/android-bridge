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
