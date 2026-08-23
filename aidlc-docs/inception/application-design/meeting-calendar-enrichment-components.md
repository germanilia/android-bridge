# Components — Meeting Completion and Calendar Enrichment

## MeetingCalendarService

- Wraps `EKEventStore` read-only access.
- Requests EventKit permission at the first enrichment attempt.
- Converts `EKEvent` and `EKParticipant` objects into bounded local snapshots.
- Returns permission/fetch errors without blocking meeting processing.

## MeetingCalendarMatcher

- Pure logic for overlap filtering, deterministic candidate ordering, generic-domain exclusion, and customer suggestion.
- Contains no EventKit or filesystem dependency.
- Primary target for example tests and PBT invariants.

## MeetingStore Extensions

- Persists meeting end time, processing state, and selected calendar snapshot inside the meeting folder.
- Reconstructs processing/calendar state when meetings are listed after restart.
- Preserves media independently of calendar and Second Brain success.

## MeetingFinalizationCoordinator

- Implemented through existing `LinkManager` plus recorder callbacks.
- Immediately marks stopped meetings as finalizing.
- Runs final transcription/title/summary work on existing serial background queues.
- Marks completion or attention state and starts calendar enrichment asynchronously.

## Meetings UI Extensions

- Shows recording/finalizing/ready/attention state.
- Shows attached event metadata or candidate selection.
- Offers manual entry, retry, Calendar settings, and explicit Second Brain transfer.
- Removes the automatic finished-meeting sheet.
