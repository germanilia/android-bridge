# Component Methods — Meeting Completion and Calendar Enrichment

## MeetingCalendarService

- `authorizationState() -> CalendarAuthorizationState`
- `events(overlapping:start:end:completion:)`
- `openPrivacySettings()` remains an app-shell action through `NSWorkspace`.

## MeetingCalendarMatcher

- `overlapping(events:start:end:) -> [MeetingCalendarEvent]`
- `suggestedCustomer(participants:) -> String?`
- `companyLabel(email:) -> String?`

## MeetingStore

- `markEnded(meetingId:endedAtMs:)`
- `setProcessingState(meetingId:state:)`
- `setCalendarEvent(meeting:event:)`
- `clearCalendarEvent(meeting:)`
- `recoverInterruptedProcessing()`

## LinkManager

- `enrichMeetingFromCalendar(_:)`
- `selectCalendarEvent(_:for:)`
- `dismissCalendarCandidates(for:)`
- `retryMeetingFinalization(_:)`
- `openCalendarSettings()`

## MacMeetingRecorder

- `stop() -> String?` returns the stopped meeting identifier immediately while queued finalization continues.
