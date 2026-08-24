# Mobile Second Brain UX Repair Requirements

## Intent
Replace the Android Second Brain overlay-style experience with predictable mobile navigation and reliable refresh behavior, then deploy the next signed patch version to the connected phone.

## Functional Requirements
- The Second Brain opens as a full-screen destination with its own app bar.
- Android system Back and the visible Back control follow the same hierarchy:
  1. Editor to note preview.
  2. Note preview to note library.
  3. Note library to the Android Bridge screen.
- Back must not close Android Bridge while the user is inside Second Brain.
- Unsaved edits require explicit confirmation before being discarded.
- Refresh must run once per request, show visible progress, prevent overlapping scans, update the note list and selected note safely, and report success or failure.
- Search and folder browsing remain available.
- Note preview, Markdown links, editing, save, conflict cleanup, folder selection, and note creation remain available.
- The patch version changes from `0.1.0` to `0.1.1`.
- The locally debug-signed APK is installed over the existing debug-signed app on the connected Pixel 9a without clearing app data; the public `v0.1.1` APK remains release-signed.

## UX Requirements
- Use native Compose screen structure and button controls instead of clickable text glyphs and an overlay drawer.
- Give library, preview, and editor modes clear titles and actions.
- Preserve the selected note when navigating back to the library.
- Show loading, empty, and refresh states.
- Keep touch targets suitable for a phone.

## Non-Goals
- No storage format, Syncthing, Markdown parser, protocol, Mac app, or release-channel redesign.
- No new UI dependency.

## Acceptance Criteria
- Connected-device Back from a note shows the library; Back from the library shows Android Bridge.
- Refresh cannot overlap and visibly completes with current note data.
- A dirty editor cannot be dismissed without Save or Discard confirmation.
- Android unit tests and APK build pass.
- `adb install -r` succeeds and reports version `0.1.1` while preserving the package data and SAF folder grant.
