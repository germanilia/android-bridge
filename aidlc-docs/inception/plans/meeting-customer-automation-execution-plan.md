# Meeting customer automation execution plan

## Scope and risk

- **Primary components:** `MeetingCalendar`, new local customer store, `LinkManager`, Meetings SwiftUI, Settings SwiftUI, BridgeCore tests.
- **User-facing impact:** Customer assignment and calendar enrichment behavior change.
- **Data-model impact:** New local catalog/association JSON and optional calendar identifier/source in event snapshots.
- **Protocol impact:** None.
- **Infrastructure impact:** None.
- **Risk:** Medium. Incorrect matching could file a meeting under the wrong customer, so uncertain matches fail to a user choice.
- **Rollback:** Remove the new local JSON file and revert the targeted Mac files. Existing meeting data remains readable.

## Stage decisions

- Workspace Detection: completed.
- Reverse Engineering: skipped. Existing calendar design artifacts and source are current.
- Requirements Analysis: completed with five recommended answers.
- User Stories: skipped by explicit request for direct implementation; acceptance criteria cover the single owner-user workflow.
- Workflow Planning: completed.
- Application Design: skipped. The change adds one focused local store behind existing `LinkManager` orchestration; interfaces are specified in the code-generation plan.
- Units Generation: skipped. One Mac-side unit is sufficient.
- Functional Design: skipped. Deterministic rules are fully specified in requirements and tests.
- NFR Requirements and NFR Design: skipped. Existing local Swift/EventKit stack, security rules, and SwiftCheck setup remain unchanged.
- Infrastructure Design: skipped. No infrastructure changes.
- Code Generation: execute test-first.
- Build and Test: execute full Mac validation and signed app installation.

## Change sequence

1. Pin customer matching, persistence, tolerance, and backward compatibility with failing tests.
2. Add the customer catalog and association store.
3. Extend EventKit snapshots, calendar listing, preferred-calendar filtering, and tolerant matching.
4. Wire catalog, learned matching, prompts, and settings through `LinkManager`.
5. Replace customer free-text fields with one searchable picker.
6. Add preferred-calendar and association management to Settings.
7. Run tests, build, package, sign, install, and relaunch.

## Success criteria

- All acceptance criteria in `meeting-customer-automation-requirements.md` pass.
- Swift XCTest and SwiftCheck pass.
- `MacCheck`, Swift build, package signing, install verification, and relaunch pass.
- No customer or calendar details enter activity or diagnostic logs.
- Existing unrelated working-tree changes remain intact.
