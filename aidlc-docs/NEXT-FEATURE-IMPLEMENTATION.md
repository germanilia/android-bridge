# Next Feature Implementation Plan

**Updated**: 2026-07-05T09:12:20Z
**Workflow status**: Inception, construction, and build/test are complete for U1-U12. The project is now in post-construction feature-hardening increments.

## Current implementation state

The repo contains working native apps and shared protocol code:

- `protocol/` — Kotlin and Swift Device-Link protocol implementations with round-trip tests.
- `android/` — Kotlin/Compose Android app with foreground service, TLS link, NSD discovery, notification/SMS/call/file/clipboard/screen plumbing.
- `mac/` — SwiftUI/AppKit macOS app with TLS link, Bonjour discovery, call UI, clipboard/files/screen windows, and notifications.

Recent call-control fix:

- Mac sends protocol-aligned `call.action` values: `answer`, `decline`, `dial`.
- Android accepts both the protocol names and legacy aliases: `answer`/`accept`, `decline`/`hangup`.
- Android dialing uses `TelecomManager.placeCall(...)` on modern Android, with legacy `ACTION_CALL` fallback for old API levels.

Validation after the fix:

- Android unit tests: `cd android && ./gradlew :app:testDebugUnitTest --no-daemon` — passed.
- Mac tests: `cd mac && swift test` — passed.

## Remaining hardware-verification work

These items need a real Android phone and Mac on the same trusted LAN:

1. Pairing and reconnection over Bonjour/NSD.
2. Mac-to-phone dialing from the Mac Phone section.
3. Incoming call banner, answer, and decline from Mac.
4. Phone call state transitions and permission behavior on the target Samsung/Android version.
5. Notification listener and SMS receiver behavior with real permissions.
6. File transfer both directions with large files.
7. Screen capture approval and frame streaming.
8. Clipboard sync behavior with foreground/background constraints.

## Next feature increments

### Increment 1 — Call control hardening

Goal: make regular cellular call control from Mac reliable before adding Bluetooth audio.

Tasks:

- Add explicit call permission status to Android UI and Mac activity messages.
- Report call-action result back to Mac with a protocol message or event.
- Add active call state updates from Android to Mac: ringing, dialing, active, ended.
- Confirm `TelecomManager.placeCall(...)`, `acceptRingingCall()`, and `endCall()` behavior on the target Samsung phone.
- Add a user-facing fallback message if the phone/OEM blocks a call action.

### Increment 2 — Bluetooth HFP feasibility spike ✅ COMPLETE (hardware-validated)

Goal: prove the final call-audio route. **Findings: `aidlc-docs/increments/increment-2-hfp-feasibility.md`.**

**Verdict: NOT viable on the target hardware (S23 Ultra + M1 Mac).** HFP *control* works (the Mac
connects as a Hands-Free unit and sees `call active = 1`), but the **SCO audio link fails to
establish** (`BTM_CreateSco Fail` / `HFSCO-SCO fail reason 13`) — call audio stays on the phone.
It's a macOS/controller-level SCO limitation, not fixable from the app.

Question-by-question (final):

- System pairing alone → not sufficient; macOS won't act as a phone's headset natively.
- Audio to Mac speakers/mic while Wi-Fi controls → **NO** — control link comes up, SCO audio does not.
- Minimum integration → moot; native audio routing is not achievable, so **Option C is dropped**.
- Manual fallback → **this is the shipping path** (see Increment 2b below).

Decision: **do not build an HFP audio bridge.** Keep `mac/Sources/HfpProbe` +
`scripts/make-hfp-probe-app.sh` for re-testing on future macOS releases.

### Increment 2b — Manual call-audio experience (replaces the HFP audio work) ✅ DONE

Goal: make calls-from-the-Mac genuinely usable given audio can't route to the Mac.

Delivered:

- ✅ Fixed the duplicate incoming-call notification (Android fires RINGING twice; the redundant
  Mac toast stacked — dropped it, the interactive call panel is the incoming UI).
- ✅ Honest audio copy on both call panels: "Audio plays on your phone or a paired headset."
- ✅ **Active-call experience**: new `call.state` protocol message (ringing/active/ended);
  Android `CallStateReceiver` now reports OFFHOOK→active and IDLE→ended (carrying the last
  ringing number); Mac swaps the ringing panel for an **in-call panel** with caller, a **live
  elapsed timer**, and **End Call**, and dismisses it when the call ends.

Architecture (final):

- Wi-Fi/TLS for call metadata + controls (dial / answer / decline / live call state). ✅
- Cellular call audio: on the phone / phone-paired headset (NOT routed to the Mac).

Possible future polish (not yet done): permission/setup checklist, contact lookup + call history
rendering on the Mac.

### Increment 3 — Product polish around calls

Goal: make the call experience feel native.

Tasks:

- Add a persistent in-call Mac panel with contact/number, elapsed time, and end-call action.
- Add permission/setup checklist for Phone, Contacts, Call Log, and Bluetooth route.
- Add contact lookup and call history rendering on Mac.
- Add clear copy: "Call audio is routed by Android Bluetooth settings; Android Bridge controls the call."

## AI-DLC process status

The original U1-U12 AI-DLC construction loop is complete. New work should be tracked as small post-construction feature increments rather than reopening the original greenfield phases, unless a feature requires major redesign.

For each new feature increment:

1. Update this plan and `aidlc-state.md`.
2. Implement the smallest scoped change.
3. Run the relevant Android and Mac tests.
4. Record hardware-verification results when tested on devices.
