# Unit of Work — MCAL1 Meeting Calendar Experience

## Responsibility

Deliver the complete Mac-side meeting completion and calendar enrichment experience as one atomic increment.

## Included Work

- Pure event overlap and customer inference logic.
- EventKit read-only adapter.
- Meeting end/state/calendar snapshot persistence.
- Non-blocking Mac and phone completion orchestration.
- Processing and calendar candidate published state.
- Inline Meetings status, event chooser/manual entry, retry/settings actions.
- Removal of automatic finished-meeting Second Brain sheet.
- Calendar usage descriptions, tests, build, signing, install, and relaunch.

## Code Locations

- `mac/Sources/BridgeCore/`
- `mac/Sources/BridgeApp/`
- `mac/Tests/BridgeCoreTests/`
- `mac/scripts/make-macos-app.sh`

No Android or protocol change is required.
