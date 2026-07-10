# Code Summary — U12 Android App Shell (Compose)

**Status: DONE — debug APK builds and runs; 24 unit tests pass; emulator-verified.** The Compose shell,
foreground service, and a complete manifest are in place. The APK installs and launches on an emulator
(UI renders); live cross-device link/services still need real hardware.

## What exists
- `android/app/src/main/kotlin/com/androidbridge/MainActivity.kt` — Compose UI wired to the core: device
  identity + fingerprint card, paste-QR pairing, paired-device list with unpair, per-feature toggle switches.
- `android/app/src/main/kotlin/com/androidbridge/android/LinkForegroundService.kt` — foreground service +
  ongoing `link_status` notification (`START_STICKY`, `connectedDevice` type).
- `android/app/src/main/AndroidManifest.xml` — **complete**: `MainActivity` (launcher) +
  `LinkForegroundService` (`foregroundServiceType=connectedDevice`) + `NotificationListener`
  (BIND_NOTIFICATION_LISTENER_SERVICE + intent filter) + permissions (INTERNET, ACCESS_NETWORK_STATE,
  CHANGE_WIFI_MULTICAST_STATE, POST_NOTIFICATIONS, FOREGROUND_SERVICE[_CONNECTED_DEVICE], RECEIVE_SMS,
  READ_SMS, READ_CONTACTS, READ_CALL_LOG, BLUETOOTH_CONNECT). *(The earlier "manifest gap" note is obsolete.)*
- Gradle build: `android/{settings,build}.gradle.kts`, `app/build.gradle.kts` (Compose, kotlinx-serialization,
  security-crypto, coroutines, Kotest; `:protocol` dep), wrapper at Gradle 8.10.2.

## Build / test (passing)
- `cd android && ./gradlew :app:assembleDebug` → `app/build/outputs/apk/debug/app-debug.apk` (~32 MB). ✅
- `cd android && ./gradlew :app:testDebugUnitTest` → **24 unit tests, 0 failures** (Kotest, JUnit platform). ✅
- **Emulator run** (AVD `bridge34`, arm64 system image): `adb install -r …app-debug.apk` then launch →
  `MainActivity` resumes, UI renders (identity/fingerprint, pairing, paired list, feature toggles), no crash. ✅

## Not yet implemented / not verified
- Multi-screen `NavHost` + dedicated ViewModels; DI graph connecting the foreground service to a live
  `ConnectionService`; onboarding flow; the live cross-device link (depends on U3 transport + real NSD).
- Live services / real device features (notification/SMS/telephony/screen/BT) need a physical phone — not
  verified here. No instrumented (`androidTest`) tests yet.

**Verification: ✅ APK builds, installs + launches on emulator, 24 unit tests green; live cross-device runtime not hw-verified.**
