# Code Summary — MCAL1 Meeting Calendar Experience

## Created

- `mac/Sources/BridgeCore/MeetingCalendar.swift`
  - EventKit authorization/read adapter.
  - Codable event/participant snapshots.
  - Pure overlap matching and conservative customer inference.

## Modified

- `mac/Sources/BridgeCore/MeetingCapture.swift`
  - Persists end time, processing state, and selected calendar snapshot.
  - Recovers interrupted finalization as `Needs Attention`.
  - Supports retry and calendar title snapshots without moving the folder.
- `mac/Sources/BridgeCore/MacMeetingRecorder.swift`
  - Stop returns the meeting ID immediately.
  - Finalization uses a separate queue so a new meeting's chunks are not blocked by the prior summary/title work.
- `mac/Sources/BridgeCore/LinkManager.swift`
  - Phone stop no longer finalizes synchronously on the receive path.
  - Publishes finalization and calendar candidate/status state.
  - Automatically applies one event, exposes multiple candidates/manual entry, and supports retry/settings.
  - Company edits no longer create a new Second Brain note unless that meeting was previously transferred.
- `mac/Sources/BridgeApp/BridgeApp.swift`
  - Removes the automatic finished-meeting sheet.
  - Adds processing labels, inline Calendar details/selection/manual flow, and retry actions.
  - Keeps Second Brain transfer explicit.
- `mac/scripts/make-macos-app.sh`
  - Adds Calendar privacy usage descriptions.
- `mac/Tests/BridgeCoreTests/CoreTests.swift`
  - Adds five Calendar/state tests and a SwiftCheck overlap/order property with a shrinkable domain generator.

## Story Coverage

MCAL-US-1 through MCAL-US-8 are implemented.

## Validation

- `cd mac && swift test`: 31 XCTest cases passed after incident regression coverage; both SwiftCheck properties passed 100 generated cases each.
- `cd mac && swift build`: passed.
- `cd mac && swift run MacCheck`: 14/14 checks passed.
- `git diff --check`: passed.
- `bash -n mac/scripts/make-macos-app.sh`: passed.

## Extension Compliance

- **Security**: EventKit only; no Gmail/API key/backend; no sensitive calendar fields added to logs; calendar failures apply no metadata.
- **Resiliency**: Disabled.
- **Partial PBT**: PBT-03, PBT-07, PBT-08, and PBT-09 satisfied; PBT-02 N/A because no new wire serialization was added.
- **Blocking findings**: None.

## Deployment

- Release app built and signed with `android-bridge`.
- Installed to `/Applications/AndroidBridge.app` and relaunched.
- Current built and installed executable SHA-256 after permission-persistence recovery: `0456e1db8cbe13e098a25c12234a0f18a81932154c0d9cb7be85519415d517fe`.
- Installed Info.plist contains both Calendar usage descriptions.
- Installed process confirmed running.

## Remaining Manual Validation

Grant Calendar access once, stop a short meeting, and verify one-event auto-match plus multiple-event/manual-choice behavior against real local calendars.
