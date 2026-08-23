# macOS Permission Persistence Recovery Plan

## Root Cause

- macOS TCC binds Calendar, Microphone, and Screen Recording grants to the app's designated code requirement.
- The installed requirement currently uses bundle ID `com.androidbridge.mac` plus certificate leaf `A0B15CA62926F788FFFC550CA7A7737AA64C7699`.
- Packaging currently selects the first valid keychain identity. With multiple identities installed, selection is not an explicit app invariant.
- Packaging also suppresses signing failure and continues installation, which can silently change the app identity and invalidate TCC grants.
- Screen Recording still has a stale requirement from an older build identity; Calendar was manually reset during the prior recovery, which explains that additional prompt.

## Steps

- [x] Inspect installed signature, designated requirement, certificates, packaging script, and TCC mismatch evidence.
- [x] Make the signing identity deterministic and fail fast when unavailable or signing fails.
- [x] Refuse installation when the new and currently installed designated requirements differ unless explicitly overridden.
- [x] Stage and verify the complete bundle before replacing `/Applications/AndroidBridge.app`, then verify again after installation.
- [x] Add an explicit Screen Recording request action in the app.
- [x] Build/test, install repeatedly, and verify the designated requirement remains identical.
- [x] Reset only the stale Screen Recording registration once; Calendar was not reset and its grant remains intact.
- [x] Relaunch, confirm zero Calendar prompts/TCC row changes across repeated updates, open Screen Recording settings for the one required user grant, and update records.

## Safety

- Preserve the current Calendar grant and all meeting data.
- Never grant privacy permission programmatically; macOS requires one explicit user approval.
- Abort updates rather than installing a build whose identity would invalidate existing grants.
