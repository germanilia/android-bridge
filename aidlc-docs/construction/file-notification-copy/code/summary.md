# File Notification Copy Code Summary

## Modified Application Code
- `mac/Sources/BridgeApp/main.swift`
  - Selects toast Copy text from `userInfo["path"]` when path metadata exists.
  - Retains the visible notification body as the Copy value for all other toasts.
  - Leaves click-to-open behavior unchanged.

## Verification
- `swift test`: 25 XCTest cases passed; SwiftCheck reported 100 passing property cases.
- `swift build`: passed.
- Release app built with `mac/scripts/make-macos-app.sh`.
- Installed binary matches the built binary SHA-256: `867fcb85aa48f86245ee8d22ec79de9a5669f5b3691b7e82a28d157906b97a15`.
- `/Applications/AndroidBridge.app` relaunched; process confirmed running.

## Deployment Note
The app uses the stable `android-bridge` signing identity. `codesign --verify --deep --strict` still reports a pre-existing packaging issue: the bundled MLX Whisper virtual environment contains an absolute Python symlink outside the app bundle. This change did not introduce or modify that packaging behavior.

## Compliance
- **Security Baseline**: The changed behavior is compliant. Copy requires explicit local user action and introduces no network, storage, authentication, input, dependency, or permission changes. SECURITY-01 through SECURITY-12 and SECURITY-14 are N/A; SECURITY-13 is unchanged; SECURITY-15 remains compliant for this local UI path.
- **PBT partial mode**: PBT-02, PBT-03, PBT-07, and PBT-08 are N/A to the UI selection. PBT-09 remains compliant through SwiftCheck; existing property suite passed.
- **Resiliency Baseline**: Disabled; skipped.
