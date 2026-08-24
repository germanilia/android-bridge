# Mobile Second Brain UX Repair Code Generation Plan

## Context
- Existing native Android/Compose application.
- Existing SAF-backed `SecondBrainFolder` and `LinkManager` remain the data boundary.
- User authorized implementation, version bump, connected-device install, commit, push, and publication.

## Plan
- [x] Step 1: Inspect the current Second Brain UI, refresh path, release versioning, and connected device.
- [x] Step 2: Record minimal requirements and define the native library/preview/editor navigation hierarchy.
- [x] Step 3: Add failing tests for Back navigation and refresh request serialization.
- [x] Step 4: Implement testable navigation and refresh-state behavior.
- [x] Step 5: Replace the overlay/drawer UI with a full-screen Compose library, note preview, and editor.
- [x] Step 6: Add unsaved-edit confirmation and accessible native actions.
- [x] Step 7: Bump `VERSION` to `0.1.1`.
- [x] Step 8: Run Android tests, assemble the APK, and review the diff.
- [x] Step 9: Build and verify the release-signed APK; install the signer-compatible debug APK with `adb install -r`, then verify version plus launch state on the Pixel 9a without clearing Second Brain data.
- [ ] Step 10: Update AI-DLC evidence, commit, push, observe CI, and publish stable `v0.1.1`.

## Traceability
Steps 3-6 satisfy navigation, refresh, loading, and dirty-editor requirements. Steps 7-10 satisfy versioned deployment and publication requirements.
