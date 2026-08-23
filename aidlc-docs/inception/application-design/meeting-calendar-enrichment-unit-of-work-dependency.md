# Unit Dependency — MCAL1 Meeting Calendar Experience

## Dependencies

| Dependency | Type | Requirement |
|---|---|---|
| Existing MeetingStore | Internal | Extend in place; preserve existing meeting folders |
| Existing MacMeetingRecorder | Internal | Return stopped ID and retain serial ordering |
| Existing LinkManager | Internal | Coordinate without blocking network receive path |
| EventKit | macOS platform | Read-only event access |
| Existing Meetings SwiftUI | Internal | Add inline state/actions; remove completion sheet |
| Existing SecondBrainExporter | Internal | Invoke only through explicit action |
| SwiftCheck/XCTest | Test | Cover pure invariants and examples |

## Delivery Order

Pure tests and calendar domain logic → persistence → orchestration → UI → bundle metadata → full verification/install.
