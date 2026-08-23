# Clipboard and Second Brain reliability code summary

## Clipboard

### Android

- `android/app/src/main/kotlin/com/androidbridge/MainActivity.kt`
  - Auto Sync toggle persisted through `LinkManager`.
  - Foreground clipboard listener now follows the tested manual/auto policy.
  - Manual Push Clipboard remains available.
  - Activity UI no longer prints clipboard contents.
- `android/app/src/main/kotlin/com/androidbridge/core/LinkManager.kt`
  - Manual is the runtime default.
  - Clipboard text is limited to 900,000 UTF-8 bytes before protocol framing.
  - Inbound text posts a private notification with a Copy action.
  - Sent/received events contain no copied text.
  - Copy-action echo suppression expires after two seconds.
- `android/app/src/main/kotlin/com/androidbridge/android/ClipboardCopyReceiver.kt`
  - Copy action suppresses the corresponding listener echo before writing `ClipboardManager`.

### Mac

- `mac/Sources/BridgeCore/LinkManager.swift`
  - Manual is the runtime default.
  - Auto Sync setting persists in `UserDefaults`.
  - Pasteboard polling uses `ClipboardSyncPolicy`.
  - Manual Push Clipboard remains available.
  - Inbound clipboard still becomes the Mac pasteboard, with change-count echo suppression.
  - Activity events contain no clipboard text.
- `mac/Sources/BridgeApp/BridgeApp.swift`
  - Clipboard section exposes Auto Sync and explains the active mode.

## Second Brain

### Android

- `android/app/src/main/kotlin/com/androidbridge/core/SecondBrainFolder.kt`
  - External scans clear stale content cache.
  - Read, create-directory, create-file, write, and delete failures throw instead of silently returning.
  - Concurrent cache access uses `ConcurrentHashMap`.
- `android/app/src/main/kotlin/com/androidbridge/core/LinkManager.kt`
  - Refresh updates tree, selected persisted content, conflict count, note count, and refresh time.
  - CRUD/search/conflict failures produce safe actionable status and content-free diagnostics.
- `android/app/src/main/kotlin/com/androidbridge/MainActivity.kt`
  - Brain tab refreshes every three seconds while visible.
  - Unsaved drafts block selected-note replacement during refresh.
  - New-note navigation waits for successful file creation.
  - Folder, note count, refresh time, and errors are visible.

### Mac

- `mac/Sources/BridgeCore/SecondBrainStore.swift`
  - Root and second-brain skill settings are read live.
  - `revision()` detects Markdown path, size, or modification-time changes.
- `mac/Sources/BridgeCore/LinkManager.swift`
  - Serialized refresh queue compares revisions before expensive tree reload.
  - Folder change refresh updates tree/content/status off the UI thread.
  - File errors show safe messages; details are reduced to error type in diagnostics.
- `mac/Sources/BridgeApp/BridgeApp.swift`
  - Brain tab refreshes on every appearance and checks every three seconds while visible.
  - Unsaved drafts are not replaced by background refresh.
  - Root path, note count, refresh time, and errors are visible.

Syncthing remains the network synchronization owner. No protocol, infrastructure, or dependency changed.

## Tests and artifacts

- Android app tests: 46 passed.
- Android protocol tests: passed.
- Android debug APK: `android/app/build/outputs/apk/debug/app-debug.apk`.
- APK SHA-256: `473ade92019f8c8e00aecb4db0ebefbcdc2cd6be09ed9243209f987aeceef409`.
- Mac XCTest: 33 passed.
- Mac SwiftCheck: two 100-case properties passed.
- `MacCheck`: 14 passed.
- Swift protocol XCTest: 8 passed.
- Swift protocol property runs and `ProtocolCheck`: passed.
- Signed Mac app installed and relaunched.
- Built/installed Mac executable SHA-256: `3f68f2d7714325217ce554ea1a64702b98726e405a676d600d953e5f771bfc15`.

## Remaining hardware verification

After the Android phone connects:

1. Install the prepared APK with `adb install -r`.
2. Verify manual and Auto Sync clipboard behavior both directions.
3. Verify the Android Copy notification.
4. Create/edit Second Brain notes from both devices and confirm visible-tab refresh.
5. Confirm the phone Syncthing folder and home-server convergence state.
