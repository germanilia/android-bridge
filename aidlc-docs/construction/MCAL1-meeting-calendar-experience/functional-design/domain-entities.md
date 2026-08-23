# Domain Entities — MCAL1

## MeetingProcessingState

`recording`, `finalizing`, `ready`, `needsAttention`.

## MeetingCalendarParticipant

- Display name
- Optional email
- Current-user flag

## MeetingCalendarEvent

- Stable event identifier
- Title
- Start/end
- Calendar title
- Optional organizer
- Participants
- Optional meeting URL and location

## MeetingRecord Extensions

- End date
- Processing state
- Optional selected calendar event snapshot

## Transient Candidate State

`meetingId -> [MeetingCalendarEvent]`, published by LinkManager and not persisted because EventKit can re-query it.
