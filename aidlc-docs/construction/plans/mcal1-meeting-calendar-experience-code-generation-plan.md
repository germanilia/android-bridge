# Code Generation Plan — MCAL1 Meeting Calendar Experience

## Unit Context

- **Stories**: MCAL-US-1 through MCAL-US-8.
- **Dependencies**: Existing MeetingStore, MacMeetingRecorder, LinkManager, BridgeApp Meetings UI, EventKit, XCTest, SwiftCheck.
- **Owned data**: Processing state, end time, selected calendar event snapshot.
- **Code location**: Existing `mac/` Swift package only; documentation remains under `aidlc-docs/`.

## Execution Steps

- [x] **Step 1 — Load design and inspect brownfield files.** Confirm exact files and preserve unrelated uncommitted work.
- [x] **Step 2 — Write failing tests first.** Added examples and PBT for overlap matching, customer inference, processing-state persistence, and interruption recovery; `swift test` failed as expected because the new domain and store APIs did not exist.
- [x] **Step 3 — Add calendar domain and EventKit adapter.** Created `mac/Sources/BridgeCore/MeetingCalendar.swift` with bounded snapshots, matcher/inference, permission, and event fetch.
- [x] **Step 4 — Extend meeting persistence.** Modified `MeetingCapture.swift` for end time, processing state, calendar snapshot, and interrupted-state recovery.
- [x] **Step 5 — Make completion non-blocking.** Modified `MacMeetingRecorder.swift` and `LinkManager.swift` so stop returns immediately, network routing does not finalize synchronously, processing state is visible, and retry is available.
- [x] **Step 6 — Remove automatic popup and add inline UI.** Modified `BridgeApp.swift` with processing labels, calendar candidate selection, manual entry, retry/settings actions, and explicit Second Brain transfer only.
- [x] **Step 7 — Add Calendar usage descriptions.** Modified `mac/scripts/make-macos-app.sh` for EventKit privacy strings.
- [x] **Step 8 — Run focused and full validation.** `swift test` passed 30 XCTest cases plus 2×100 SwiftCheck cases, `swift build` passed, MacCheck passed 14/14, shell syntax and diff checks passed, and Calendar privacy keys are present.
- [x] **Step 9 — Generate code summary and update AI-DLC state/build records.** Recorded files, story coverage, extension compliance, validation results, and deployment status.
- [x] **Step 10 — Build, sign, install, and relaunch existing app.** Built release, signed with `android-bridge`, installed to `/Applications/AndroidBridge.app`, verified both Calendar privacy keys, confirmed built/installed SHA-256 equality, and confirmed the installed process is running.

## Approval

The user explicitly approved implementation and requested no further questions. This authorizes the complete sequence above using documented defaults.
