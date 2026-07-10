# Code Summary — U10 Settings & Permissions

**Status: DONE (toggle logic) — unit tests green.** Per-feature enable/disable is implemented in both
languages and surfaced in both shells' UIs. OS runtime-permission prompts and effective-state degradation
are device/OS flows, not verified here.

## What exists
- **Kotlin** — `core/PluginRegistry.kt`: `FeatureId {NOTIFICATIONS, SMS, FILES, CLIPBOARD, SCREEN, CALLS}`
  + `enable`/`disable`/`isEnabled`/`enabled` (default = all enabled). Toggles rendered in the Compose UI
  (`MainActivity.kt`). Persistence available via `SecureStore`/`AndroidSecureStore` (shared with U2).
- **Swift** — `BridgeCore/Core.swift` `PluginRegistry`; SwiftUI `Toggle`s in `BridgeApp/BridgeApp.swift`.

## Tests (passing)
- Kotlin `PluginRegistryTest` (all enabled by default; disable→enable). Run: `./gradlew :app:testDebugUnitTest` ✅
- Swift `MacCheck`: registry default + toggle checks. ✅

## Not yet implemented / not verified
- `PermissionService` (Android special-access + runtime grants; macOS TCC / Local Network / Bluetooth);
  `effectiveState = enabled && allGranted` resolver + fix-it hints (US-9.3); settings-snapshot persistence
  schema; guided permission-prompt UI in the shells.
- Real permission grant/revoke flows require a device/Xcode — not verified here.

**Verification: ✅ toggle logic green both languages (`PluginRegistryTest`/`MacCheck`); permission flows pending + not hw-verified.**
