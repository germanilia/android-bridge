# Application Design — Meeting Completion and Calendar Enrichment

## Design Summary

The increment stays inside the existing Mac app. It adds a small EventKit adapter, pure calendar matching/customer inference, local meeting metadata persistence, non-blocking completion orchestration, and inline Meetings UI actions.

## Key Boundaries

- **Platform boundary**: `MeetingCalendarService` owns EventKit access.
- **Business logic boundary**: `MeetingCalendarMatcher` owns deterministic overlap and customer rules.
- **Persistence boundary**: `MeetingStore` owns local state and event snapshots.
- **Orchestration boundary**: `LinkManager` owns background completion, enrichment, retry, and published UI state.
- **UI boundary**: `BridgeApp` renders states and explicit actions; it does not call EventKit directly.

## State Model

- `Recording`: capture active.
- `Finalizing`: capture stopped; queued transcript/summary work remains.
- `Ready`: local meeting output is usable.
- `Needs Attention`: recoverable completion failure.

Calendar candidate ambiguity is separate from processing state so a ready meeting can require event selection without appearing failed.

## Persistence

Each meeting folder may contain:

- `endedAt.txt`
- `processingState.txt`
- `calendar-event.json`

Candidate lists are transient and can be queried again. The selected event is a stable local snapshot.

## Security

- EventKit read permission only; no Gmail or calendar-write access.
- Calendar-derived values are sanitized by existing meeting/customer path boundaries.
- Participant details, calendar URL, customer data, and transcript content are not logged.
- Calendar failure is fail-safe: no metadata is applied and the local meeting remains available.

## PBT

- PBT-03: every returned candidate overlaps the meeting range; reordering input does not alter the ordered result.
- PBT-07: generators constrain valid start/end ranges.
- PBT-08/PBT-09: existing SwiftCheck shrinking and seed behavior remain active.

## Blocking Findings

None.
