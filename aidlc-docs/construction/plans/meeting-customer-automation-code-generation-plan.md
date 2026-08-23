# Meeting customer automation code-generation plan

This plan is the implementation source of truth for the single Mac-side feature unit.

## Context

- Requirements: `aidlc-docs/inception/requirements/meeting-customer-automation-requirements.md`
- Execution plan: `aidlc-docs/inception/plans/meeting-customer-automation-execution-plan.md`
- Existing dependencies: EventKit, SwiftUI, MeetingStore, SecondBrainExporter, SwiftCheck.
- New dependencies: none.

## Steps

- [x] Step 1: Added failing example and property tests for tolerant event matching, customer matching, association persistence, catalog deduplication, and old event snapshot decoding.
- [x] Step 2: Focused tests failed as expected because the customer store/matcher, calendar identity fields, and tolerance API do not exist.
- [x] Step 3: Implemented the local customer catalog and learned calendar association persistence with input bounds and atomic writes.
- [x] Step 4: Extended calendar snapshots and EventKit service with stable calendar identifiers, calendar listing, calendar filtering, and 15-minute tolerance.
- [x] Step 5: Wired customer catalog refresh, safe automatic matching, unresolved-customer prompts, learned association correction, and preferred calendar into `LinkManager`.
- [x] Step 6: Added one reusable searchable customer picker for meeting editing, calendar resolution, and Second Brain transfer.
- [x] Step 7: Added preferred-calendar and learned-association controls to Settings.
- [x] Step 8: Focused tests, 40-test Swift suite, three SwiftCheck properties, Swift build, MacCheck 14/14, privacy searches, and static validation passed.
- [x] Step 9: Generated code/build summaries and updated state/audit records.
- [x] Step 10: Packaged, signed, installed, relaunched, and matched built/installed executable SHA-256 `e9ceae282110bd4bfa4e2ee073514e66a57ce67c5a5eb66b67aeef81e43ebfc1`.
- [x] Step 11: Verified no duplicate source files, temporary debug markers, privacy leaks, whitespace errors, or edits outside the targeted feature/docs surfaces.

## Security compliance targets

- SECURITY-01: local storage inherits FileVault/data-volume encryption; no network store added.
- SECURITY-03: no customer, participant, title, URL, or association content in logs.
- SECURITY-05: bound and normalize customer names and persisted fields.
- SECURITY-09: user-facing errors reveal no internal paths or payloads.
- SECURITY-10: no dependency change.
- SECURITY-13: validate JSON decoding and preserve backward compatibility.
- SECURITY-15: fail to user selection on ambiguity or persistence failure.

## PBT targets

- PBT-02: association state JSON round-trip.
- PBT-03: event matches always intersect the padded interval; input order does not change results; ambiguous associations never auto-select.
- PBT-07: generated calendar intervals and association signals obey domain constraints.
- PBT-08: SwiftCheck shrinking and seed output remain enabled.
- PBT-09: use existing SwiftCheck dependency.
