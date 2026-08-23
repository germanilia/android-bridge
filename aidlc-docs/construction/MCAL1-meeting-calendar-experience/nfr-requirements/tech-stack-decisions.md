# Tech Stack Decisions — MCAL1

| Concern | Decision | Rationale |
|---|---|---|
| Calendar access | Apple EventKit | Platform-native, reads configured Google calendars, no OAuth/backend/dependency |
| Async work | Existing DispatchQueue/callback model | Matches codebase and macOS 13 deployment target |
| Persistence | Small Codable/text files in meeting folder | Backward-compatible and recoverable without database migration |
| UI | Native SwiftUI Menu, Label, Button, SectionBox | Consistent, accessible, minimal new code |
| Example tests | XCTest | Existing project test runner |
| Property tests | SwiftCheck | Existing PBT-09 framework with shrinking/seeds |

No new dependency or credential is introduced.
