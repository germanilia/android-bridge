# Clipboard and Second Brain reliability requirements

## Intent analysis

- **Request:** Explain and repair clipboard sharing, then repair stale Second Brain entries in the Android and Mac apps.
- **Type:** Existing-feature enhancement plus defect repair.
- **Scope:** Android app, macOS app, shared clipboard behavior, local Second Brain stores, and tests.
- **Complexity:** Moderate. Existing transport and Syncthing architecture remain unchanged.
- **Deployment:** Build and update the Mac app now. Build the Android APK now; install it after the phone connects.

## Locked decisions

- Clipboard text remains the only clipboard payload.
- Clipboard sharing defaults to manual on both devices.
- Each device has a persistent Auto Sync toggle.
- Android receives Mac clipboard text through a private notification with a Copy action. It does not replace the system clipboard automatically.
- Second Brain remains a local Markdown folder synchronized by Syncthing. Android Bridge does not add another sync protocol.
- Both apps refresh on view entry and while the Second Brain view remains visible.
- Manual Refresh remains available.
- Both apps show the local folder, note count, last refresh, and actionable failures.

## Functional requirements

### CSR-FR-1: Clipboard policy

1. Manual push sends the current text clipboard while connected.
2. Auto Sync is disabled by default and persists independently on Android and Mac.
3. Mac polls `NSPasteboard` only for change detection and sends changed non-empty text only when Auto Sync is enabled.
4. Android observes clipboard changes only while its activity is foregrounded, as required by Android clipboard restrictions, and sends only when Auto Sync is enabled.
5. Runtime paths use the same manual/auto policy that unit tests exercise.

### CSR-FR-2: Clipboard receive behavior

1. Android stores the most recent inbound value in app state.
2. Android posts a notification that reveals no clipboard content on the lock screen and offers a Copy action.
3. The Copy action writes the inbound value to `ClipboardManager`.
4. Mac writes inbound Android text to `NSPasteboard`.
5. Applying inbound content never echoes it back to the sender.
6. Activity events state that a clipboard was sent or received without including its content.

### CSR-FR-3: Clipboard boundaries and feedback

1. Clipboard messages remain encrypted by the existing pinned TLS link.
2. Empty automatic clipboard values are ignored.
3. Oversized values fail without breaking the connection and produce safe user feedback.
4. Images and copied files remain outside clipboard scope. Files use existing file transfer.

### CSR-FR-4: Second Brain refresh

1. Mac refreshes its Second Brain every time the tab appears.
2. While the Mac tab is visible, it detects local Markdown metadata changes and refreshes only when the folder changed.
3. Android refreshes every time the Brain tab appears and periodically while it remains visible.
4. Android invalidates stale note-content cache entries before external refresh reads.
5. Selected note content updates after an external Syncthing change without overwriting an unsaved editor draft.
6. Manual Refresh remains available on both apps.

### CSR-FR-5: Second Brain errors and status

1. Android folder reads, writes, directory creation, output stream creation, and deletes report failures instead of silently succeeding.
2. Mac and Android show configured local folder, Markdown note count, and last successful refresh time.
3. Refresh and CRUD failures show safe actionable messages without note content.
4. The Mac store reads the current configured Second Brain root without requiring app relaunch.
5. Syncthing remains responsible for network convergence and conflict files.

## Non-functional requirements

- No new dependency or sync service.
- Refresh work runs off the UI thread.
- Visible-view polling interval is at least two seconds.
- Clipboard and note bodies never enter diagnostic or activity logs.
- Existing uncommitted meeting and UI work must remain intact.
- Kotlin and Swift builds must pass.
- Existing Android unit tests, Swift XCTest, SwiftCheck, and smoke checks must pass.
- Android hardware verification and APK installation wait for the phone connection.

## Acceptance criteria

1. Fresh installs leave clipboard Auto Sync off.
2. Enabling Auto Sync persists after relaunch.
3. Mac copy sends only in Auto mode or after Push Clipboard.
4. Android copy sends only in Auto mode while the app is foregrounded or after Push Clipboard.
5. Mac-to-Android delivery creates a private Copy notification and does not silently replace the phone clipboard.
6. Clipboard activity contains no copied text.
7. A Markdown file added to the local Syncthing folder appears in an already-open Brain tab without manual refresh.
8. Editing an open draft is not overwritten by background refresh.
9. Failed Android writes do not display a false Saved state.
10. Mac and Android show folder, count, refresh time, and errors.

## Security compliance

- **SECURITY-01:** Compliant. Existing pinned TLS remains mandatory for clipboard transport; Second Brain stays in platform-protected local folders and Syncthing.
- **SECURITY-03:** Compliant by requirement. Clipboard and note content must not enter logs.
- **SECURITY-05:** Compliant by requirement. Clipboard size and Markdown path constraints remain enforced.
- **SECURITY-09:** Compliant. User errors omit internal content and stack traces.
- **SECURITY-10:** Compliant. No dependency added; existing pinned dependencies and CI remain.
- **SECURITY-13:** Compliant. Existing typed protocol decoding remains.
- **SECURITY-15:** Compliant. External file failures must be explicit and fail the operation.
- **SECURITY-02, SECURITY-04, SECURITY-06, SECURITY-07, SECURITY-08, SECURITY-11, SECURITY-12, SECURITY-14:** N/A to this local repair. No web endpoint, cloud IAM, public network tier, authentication flow, or new credential exists.

No blocking security findings.

## Partial PBT compliance

- **PBT-02:** Existing protocol round-trip properties continue covering `clip.update` serialization.
- **PBT-03:** Manual/auto decision invariants require generated Boolean and mode coverage.
- **PBT-07:** Existing domain generators remain; clipboard mode generators are bounded enums and booleans.
- **PBT-08:** Kotest and SwiftCheck shrinking and seed output remain enabled.
- **PBT-09:** Existing Kotest Property and SwiftCheck frameworks remain selected.

No blocking PBT findings.
