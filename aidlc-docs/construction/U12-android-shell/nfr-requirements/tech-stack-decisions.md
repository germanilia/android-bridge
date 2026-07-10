# Tech Stack Decisions — U12 Android App Shell

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Language / UI** | Kotlin 2.0.21 + **Jetpack Compose** (Material 3) | Modern declarative Android UI; matches `android/app/build.gradle.kts` (compose BOM 2024.09.03). |
| **App structure** | `MainActivity` + `NavHost`, MVVM (`ViewModel` + `StateFlow`), manual DI (`AppContainer`) | Thin Composables, logic in services (BR-9); no heavyweight DI framework needed. |
| **Background host** | `LinkForegroundService` (type `connectedDevice`), `START_STICKY` | Keeps the link alive backgrounded (FR-2.2 / US-2.2). |
| **Min / target** | minSdk 33 (Android 13+), targetSdk/compileSdk 34, JDK 17 | Generic Android only (NFR-6.1 / US-10.3); per the existing Gradle config. |
| **Build / packaging** | Gradle (Kotlin DSL) → debug APK `:app:assembleDebug` | Standard Android build; needs Android SDK platform-34 + build-tools-34 + JDK 17. |
| **Protocol dependency** | `implementation(project(":protocol"))` (the Kotlin protocol module) | Shared codec/registry consumed by Core/plugins. |
| **Secure storage** | `androidx.security:security-crypto` (Keystore + EncryptedSharedPreferences) via `AndroidSecureStore` | Encryption at rest (SECURITY-01/-12) — owned by U2/U10. |
| **Concurrency** | `kotlinx-coroutines-android` + lifecycle-aware collection | `StateFlow` to Compose via `collectAsStateWithLifecycle`. |
| **PBT framework (PBT-09)** | N/A for the shell | No properties identified (PBT-01); UI tested by example/instrumented tests (PBT-10). |

## Environment deviation (recorded — must carry to Build & Test)
- The Android APK builds with `cd android && ./gradlew :app:assembleDebug`, which requires the
  **Android SDK (platform-34 + build-tools-34) and a JDK** to be installed; `android/local.properties`
  must point at the SDK. Build/run on a real device or emulator is **not performed in this environment**.
- This unit is Kotlin-only (no Swift), so the Swift/Xcode toolchain limitation does not affect U12 —
  but the Android SDK requirement above does gate any actual build here.
- Compose UI + foreground-service behavior are **device/emulator features** — not verified in this
  environment (no phone/emulator attached).

## Notes
- Dependency pinning: Gradle version catalog + dependency lockfile; scan + SBOM at Build & Test
  (SECURITY-10).
- `kotlinx.serialization` reused from the protocol layer; no third-party JSON/UI runtime deps beyond
  AndroidX + Compose.
