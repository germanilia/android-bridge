# macOS Permission Persistence Recovery — 2026-08-17

## Root Cause

macOS TCC grants are bound to an app's designated code requirement, not only its bundle ID. The packaging script selected the first valid keychain identity and suppressed signing failures. With multiple identities installed, a future order change or failed signing operation could install a different identity and invalidate Calendar, Microphone, Screen Recording, and Accessibility grants.

Calendar's latest extra prompt was also caused by the prior incident recovery explicitly resetting its TCC row. Screen Recording retained a stale row from an older app identity.

## Fix

- Pinned packaging to the existing Android Bridge signing fingerprint: `A0B15CA62926F788FFFC550CA7A7737AA64C7699`.
- Missing identity or any signing/verification failure now aborts the update.
- Compared built and installed designated requirements before replacement; an identity change is refused unless explicitly overridden.
- Staged and verified the complete bundle before replacing `/Applications/AndroidBridge.app`.
- Verified the installed bundle and requirement again after replacement.
- Added explicit `Request Screen Recording Access` UI and a first-launch request when access is off.
- Reset only the stale Screen Recording row; Calendar was not reset.

## Verification

- Installed the app repeatedly with the same requirement:
  - `identifier "com.androidbridge.mac" and certificate leaf = H"a0b15ca62926f788fffc550ca7a7737aa64c7699"`
- TCC logged zero Calendar prompts or Calendar row changes across repeated updates.
- `swift test`: 31 XCTest cases plus two SwiftCheck properties at 100 cases each passed.
- `swift build`: passed.
- `swift run MacCheck`: 14/14 passed.
- Installed app signature validates and satisfies its designated requirement.
- Current built/installed executable SHA-256 values match: `0456e1db8cbe13e098a25c12234a0f18a81932154c0d9cb7be85519415d517fe`.

## One-Time User Action

macOS does not allow an app to grant Screen Recording permission to itself. The stale row was reset and the Screen Recording settings page opened. Enable Android Bridge once and relaunch it. Subsequent updates are blocked from changing identity and therefore preserve the grant.
