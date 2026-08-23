# Meeting customer automation code summary

## Behavior

- Customer fields now use one searchable picker with existing choices and an explicit Create action.
- The catalog combines locally created customers, customer names already saved on meetings, and Second Brain client clusters.
- New customers persist locally before any Second Brain transfer.
- Calendar events use stable calendar identifiers and source labels.
- Settings allows one preferred calendar. It is searched first; all calendars are searched only when it has no qualifying event.
- Matching allows 15 minutes before recording start and after recording end.
- One qualifying event auto-selects. Multiple events keep the existing picker and sort by strongest actual overlap.
- Calendar customer matching checks learned title/calendar/domain associations first, then exact inferred organization names.
- Unresolved or conflicting matches show the customer picker instead of guessing.
- A confirmed choice is remembered for future matching events.
- Settings can change or forget learned matches.
- Meeting list editing, meeting detail, calendar resolution, and Second Brain transfer share the customer picker.

## Code

- Created `mac/Sources/BridgeCore/MeetingCustomerStore.swift`.
- Modified `mac/Sources/BridgeCore/MeetingCalendar.swift`.
- Modified `mac/Sources/BridgeCore/LinkManager.swift`.
- Modified `mac/Sources/BridgeApp/BridgeApp.swift`.
- Modified `mac/Tests/BridgeCoreTests/CoreTests.swift`.

No dependency, protocol, cloud service, calendar-write permission, or Android code changed.

## Persistence

Customer data is stored atomically at:

`~/Library/Application Support/AndroidBridge/customer-automation.json`

The file contains canonical customer names and learned event associations. Existing meeting folders and calendar snapshots remain backward-compatible.

## Validation

- Focused customer/calendar tests: 12 passed.
- Full Mac XCTest suite: 40 passed.
- SwiftCheck: customer JSON round-trip, padded event-match invariant, and stream round-trip passed 100 generated cases each.
- MacCheck: 14/14 passed.
- Swift build passed.
- Privacy and whitespace checks passed.
- Existing unrelated working-tree changes were preserved.
- Signed Mac app installed and relaunched with unchanged designated requirement.
- Built and installed executable SHA-256: `e9ceae282110bd4bfa4e2ee073514e66a57ce67c5a5eb66b67aeef81e43ebfc1`.
- Plain code-sign verification passed. Strict bundle verification still reports the pre-existing absolute Python symlink inside the bundled Whisper environment.

## Security and PBT compliance

- SECURITY-01: local data uses the existing macOS user data volume; no network store added.
- SECURITY-03: customer names, participant addresses, event titles, URLs, and association payloads are absent from logs.
- SECURITY-05: customer names are trimmed, control-character checked, and limited to 200 characters.
- SECURITY-09: errors shown in the UI omit payloads and internal paths.
- SECURITY-10: no dependency change.
- SECURITY-13: JSON decoding is validated and old calendar snapshots are tested.
- SECURITY-15: persistence failures and ambiguous matches fail to user choice.
- PBT-02, PBT-03, PBT-07, PBT-08, and PBT-09 are satisfied by the existing SwiftCheck setup and the new generated scenarios.
