# Build Instructions — android_bridge

Three buildable parts in the monorepo: the shared **protocol** (Swift + Kotlin), the **Android** app
(Gradle → APK), and the **Mac** app (SwiftPM/SwiftUI). All three build on the machine used here, and a
runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.

> **Toolchain on the build machine:** Apple Silicon Mac, JDK 23, **Xcode 26.6** (Swift 6.3; earlier work
> used Command Line Tools only), Android SDK with **platform-34 + build-tools 34.0.0** + emulator
> (`system-images;android-34;google_apis;arm64-v8a`, AVD `bridge34`), Gradle **8.10.2** (wrapper).

---

## 1. Shared protocol — Kotlin (`:protocol`, sources at `protocol/kotlin`)
- **Requires:** JDK 17+ (JDK 23 used). Gradle wrapper vendored under `android/`.
- **Build + test:** `cd android && ./gradlew :protocol:test` ✅
- Consumed by the Android app via `implementation(project(":protocol"))` (module dir `../protocol/kotlin`).

## 2. Shared protocol — Swift (`protocol/swift`)
- **Requires:** Swift 5.9+ (Xcode 26.6 present; Command Line Tools alone also build it).
- **Build:** `cd protocol/swift && swift build`
- **Test:** `swift test` → 8 XCTest tests incl. 3 SwiftCheck properties (100 cases each) ✅
- **Xcode-free smoke:** `swift run ProtocolCheck` → 9 checks / 1500 property cases ✅ (see unit-test-instructions.md).

## 3. Android app (`android/` → APK)
- **Requires:** Android SDK **platform-34 + build-tools 34.0.0**, JDK 17+, and `android/local.properties`
  with `sdk.dir`. (`compileSdk=34`, `minSdk=33`, `targetSdk=34`.)
- **Build the debug APK:** `cd android && ./gradlew :app:assembleDebug`
  → `android/app/build/outputs/apk/debug/app-debug.apk` (**~32 MB, builds today**).
- **Install:** `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

## 4. Mac app (`mac/`)
- **Requires:** Swift 5.9+ (Xcode 26.6 present). **`swift build` compiles + links** `BridgeCore`, the
  `AndroidBridge` SwiftUI app target, and `MacCheck`.
- **Build:** `cd mac && swift build` ✅ · **Tests:** `swift test` (XCTest + SwiftCheck) → 10 tests ✅
  · **Xcode-free smoke:** `swift run MacCheck` → 13 checks ✅
- **Runnable `.app`:** `mac/scripts/make-macos-app.sh` → `mac/dist/AndroidBridge.app` (Mach-O arm64,
  ad-hoc signed); `open dist/AndroidBridge.app` launches it. ✅ (Distribution notarization still needs a
  Developer ID.)

---

## Dependency pinning & supply chain (SECURITY-10)
- Swift: `Package.resolved` committed; the codec has **no runtime third-party deps**.
- Kotlin/Android: exact versions in `build.gradle.kts` (Compose BOM `2024.09.03`, `kotlinx-serialization-json
  1.7.3`, Kotest `5.9.1`, `security-crypto 1.1.0-alpha06`, coroutines `1.8.1`). To finish at release:
  commit a Gradle dependency lockfile + version catalog, run a vulnerability scan in CI, generate an SBOM.
  No `latest`/unpinned tags.

## Summary of what builds where
| Part | Builds here? | Command |
|------|:------------:|---------|
| `protocol/kotlin` | ✅ | `./gradlew :protocol:test` |
| `protocol/swift` | ✅ | `swift test` (XCTest+SwiftCheck) · `swift run ProtocolCheck` (fallback) |
| `android/` APK | ✅ | `./gradlew :app:assembleDebug` (~32 MB) |
| `android/` on emulator | ✅ | `adb install -r …app-debug.apk` (AVD `bridge34`) |
| `mac/` compile + tests | ✅ | `swift build` · `swift test` |
| `mac/` runnable `.app` | ✅ | `mac/scripts/make-macos-app.sh` |
