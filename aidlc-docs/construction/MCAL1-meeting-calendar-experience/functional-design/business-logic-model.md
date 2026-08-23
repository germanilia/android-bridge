# Business Logic Model — MCAL1

## Recording Stop

1. Stop capture and return the meeting ID.
2. Persist end time and `finalizing` state.
3. Refresh visible state immediately.
4. Queue remaining transcription/final notes work after prior chunks.
5. Persist `ready` after usable notes exist.
6. Start calendar enrichment independently.

## Event Matching

An event matches when `event.start < meeting.end` and `event.end > meeting.start`. Sort matches by absolute start-time distance, then title, then identifier for deterministic output.

## Enrichment Decisions

- Zero matches: no mutation.
- One match: persist it and fill only generic/empty title and empty customer.
- Multiple matches: publish candidates; wait for user selection, manual entry, or dismissal.
- Permission/fetch failure: publish passive error; local meeting stays ready.

## Customer Inference

1. Remove current-user participants.
2. Parse participant email domains.
3. Remove generic personal providers.
4. Normalize organization domains case-insensitively.
5. Return a title-cased label only when one unique organization remains.

## Recovery

A persisted `finalizing` state found at launch becomes `needsAttention`; Retry re-runs final notes completion from retained media/transcript.

## Testable Properties

- **PBT-03 invariant**: every match overlaps the meeting interval.
- **PBT-03 invariant**: output order/result is independent of input order.
- **PBT-07**: generated intervals always have start before end.
- **PBT-08**: SwiftCheck provides shrinking and seed reproduction.
