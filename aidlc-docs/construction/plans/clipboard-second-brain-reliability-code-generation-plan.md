# Clipboard and Second Brain reliability code generation plan

## Context

- **Stories:** CSR-US-1 through CSR-US-4.
- **Application paths:** existing Android and macOS source trees.
- **Dependencies:** existing device link, `NSPasteboard`, `ClipboardManager`, Storage Access Framework, Syncthing local folders.
- **Contract:** existing `clip.update`; no protocol schema change.
- **Approval source:** "make all the fixes, once ready tell me and ill connect the androidn phoen so you can update the versoin there"

## Steps

- [x] Step 1: Add failing Kotlin/Swift tests for clipboard policy invariants and Second Brain change detection.
- [x] Step 2: Run focused tests and confirm the new expectations fail before implementation. Swift failed because `SecondBrainStore.revision()` does not exist; Android policy PBT passed against existing pure logic.
- [x] Step 3: Wire persistent manual/auto clipboard behavior into Android and Mac runtime/UI.
- [x] Step 4: Connect Android inbound clipboard handling to a private Copy notification and remove clipboard content from activity events.
- [x] Step 5: Add Mac Second Brain root revision detection, visible-tab refresh, status, and live configured-root handling.
- [x] Step 6: Add Android periodic visible-tab refresh, cache invalidation, draft protection, explicit file errors, and status.
- [x] Step 7: Run focused tests, full Android tests/build, Swift tests/build, protocol tests, and smoke checks. All passed.
- [x] Step 8: Generate code summary and update build/test documentation.
- [x] Step 9: Package, sign, install, and relaunch the Mac app; keep Android APK ready until the phone connects.
- [x] Step 10: Verify no duplicate source files, temporary debug markers, privacy leaks, whitespace errors, or accidental edits beyond the targeted files.

## Compliance

- Security: no clipboard/note content in logs; failures explicit; existing TLS retained.
- Partial PBT: generated mode/user-action invariants; existing codec round trips and framework seed/shrinking remain.
- No new dependency.
