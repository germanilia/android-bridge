# Requirements — Meeting Completion and Calendar Enrichment

## Intent Analysis

- **User request**: Fix meeting recording completion so it no longer hangs or blocks navigation; enrich completed meetings from a Google-backed calendar; remove the automatic customer/Second Brain popup; infer a customer from calendar participants; allow event selection or manual entry when several events match.
- **Request type**: Bug fix plus user-facing feature enhancement.
- **Scope estimate**: Multiple macOS components — recording finalization, background processing, EventKit integration, meeting metadata, Meetings UI, and Second Brain transfer flow.
- **Complexity estimate**: Moderate. Native calendar access is straightforward, but recording finalization and ambiguous event matching require explicit asynchronous states.
- **Requirements depth**: Standard.

## Locked Decisions

| Area | Decision |
|---|---|
| Calendar integration | Use native macOS EventKit and calendars already configured in Apple Calendar, including Google accounts. |
| Google access | Calendar events only. Do not request Gmail message access or implement direct Google OAuth. |
| Recording completion | Stop immediately and perform remaining transcription, title, summary, and metadata work in the background. |
| Automatic popup | Remove the finished-meeting title/customer/Second Brain sheet. |
| Calendar matching | Automatically use one unambiguous overlapping event. If several events match, offer those events plus manual entry without blocking the app. |
| Customer inference | Exclude the user's addresses; infer from a single unambiguous external company/domain; otherwise leave editable customer data unset. |
| Second Brain | Transfer only after an explicit user action. |
| Extensions | Security enabled; resiliency disabled; property-based testing partial. |

## Functional Requirements

### MCAL-FR-1 — Non-Blocking Recording Stop

- Stopping a Mac or phone meeting must stop capture immediately and return control to the UI.
- Remaining chunk transcription, title generation, summary generation, note writing, and calendar enrichment must run outside the main thread and network receive path.
- The user must be able to navigate the app and start another recording while a prior meeting is finalizing.
- Meeting state must distinguish at least `Recording`, `Finalizing`, `Ready`, and `Needs Attention`.
- A failed processing step must preserve recorded media and expose a retry action.
- Finalization must not recreate a renamed meeting directory or lose a late transcript chunk.

### MCAL-FR-2 — Native Calendar Access

- Android Bridge must request read access through EventKit only when calendar enrichment is first needed.
- EventKit must read calendars already configured on macOS, including Google calendars connected through Internet Accounts.
- Permission denial must not block recording, transcription, summaries, note browsing, or manual meeting editing.
- The UI must explain how to enable Calendar permission in System Settings when access is denied.
- Android Bridge must not request Gmail scopes or access Gmail messages.

### MCAL-FR-3 — Event Matching

- Matching must use the saved meeting start and end timestamps.
- Calendar events whose time range overlaps the meeting range are candidates.
- One unambiguous candidate may be attached automatically without showing a modal.
- When several candidates match, the meeting must show a non-blocking `Choose calendar event` action.
- The chooser must list each candidate's title, calendar, start/end time, and organizer when available.
- The chooser must include `Enter manually` and `No calendar event` options.
- When no event matches, the meeting remains usable and editable without calendar metadata.

### MCAL-FR-4 — Calendar Metadata Snapshot

- A selected event may populate meeting title, scheduled start/end, calendar name, organizer, participant display names/addresses, meeting URL, and location when available.
- Imported metadata must be stored as a local meeting snapshot so the note remains stable if the calendar event later changes or disappears.
- The user must be able to edit the meeting title and customer after enrichment.
- Calendar enrichment must not overwrite an existing user-edited title or customer without explicit confirmation.

### MCAL-FR-5 — Customer Suggestion

- Customer inference must exclude participant addresses belonging to the user's configured calendar accounts.
- Generic email providers such as Gmail, Outlook, Yahoo, and iCloud must not be treated as company names.
- A single remaining external organization/domain may become the suggested customer.
- Multiple external organizations, only generic addresses, or missing participant addresses must result in no automatic customer assignment.
- The inferred customer remains editable before Second Brain transfer.

### MCAL-FR-6 — On-Request Second Brain Transfer

- Completing a recording must never open a Second Brain popup automatically.
- Each ready meeting must expose an explicit `Add to Second Brain` action.
- The action must prefill the meeting title and inferred or saved customer when available.
- The user may edit the title and customer before confirming transfer.
- Transfer must remain idempotent and update the existing Second Brain note rather than create accidental duplicates.
- Calendar enrichment and local meeting completion must succeed independently of Second Brain availability.

### MCAL-FR-7 — Meeting UI Experience

- Active and recent meetings must show processing state without taking over the window.
- Finalizing meetings must show progress text for the current stage.
- Meetings requiring calendar selection or manual customer data must show a passive attention indicator.
- Calendar selection, manual metadata entry, retry, and Second Brain transfer must be explicit actions on the selected meeting.
- No completion action may prevent browsing existing meetings or other tabs.

## Non-Functional Requirements

### MCAL-NFR-1 — Responsiveness

- Stop actions must update visible recording state within one second.
- EventKit queries, transcription, LLM calls, filesystem writes, and Second Brain commands must not execute on the main thread.
- Slow or unavailable LLM/calendar services must not block recording capture or navigation.

### MCAL-NFR-2 — Reliability

- Processing state must be recoverable after app restart from existing meeting files and metadata.
- Recorded media must remain available when transcription, summary, calendar, or Second Brain operations fail.
- Repeated finalization or enrichment must not duplicate transcript segments, meeting folders, or Second Brain notes.

### MCAL-NFR-3 — Privacy and Security

- Request the minimum EventKit read permission; do not request calendar write or Gmail access.
- Calendar and participant data must remain local and must not be included in diagnostic logs.
- Existing paired-device TLS remains unchanged.
- Calendar-derived strings must be treated as untrusted input before filesystem or Second Brain use.
- No participant email, event notes, meeting URL, transcript content, or customer data may be logged.

### MCAL-NFR-4 — Testability

- Event overlap matching and customer inference must be pure, independently testable logic.
- Tests must cover zero, one, and multiple event candidates; manual selection; generic email domains; multiple external organizations; permission denial; and retryable finalization failure.
- Partial PBT enforcement applies to matching/inference invariants, domain generators, shrinking/reproducibility, and the existing SwiftCheck framework.

## Acceptance Criteria

1. Stopping a recording immediately enables normal app navigation while final processing continues.
2. No automatic meeting-completion or Second Brain sheet appears.
3. A Google calendar configured in Apple Calendar is readable after one EventKit permission grant.
4. One overlapping event enriches the meeting automatically without overwriting user edits.
5. Multiple overlapping events produce an in-meeting chooser containing all candidates and a manual-entry option.
6. Customer suggestion uses one unambiguous external company/domain and stays empty for ambiguous or generic-domain participants.
7. `Add to Second Brain` runs only after the user invokes it.
8. Processing failures preserve media, show `Needs Attention`, and can be retried.

## Out of Scope

- Gmail message access.
- Direct Google Calendar OAuth/API integration.
- Calendar event creation or modification.
- Cloud storage or backend synchronization.
- Automatic Second Brain filing.
- Inferring a company reliably from a participant who uses only a generic personal email address.

## Extension Compliance

### Security Baseline

- **Compliant/applicable**: SECURITY-01, SECURITY-03, SECURITY-05, SECURITY-08, SECURITY-11, SECURITY-13, SECURITY-15.
- **Inherited project controls**: SECURITY-10.
- **N/A**: SECURITY-02, SECURITY-04, SECURITY-06, SECURITY-07, SECURITY-09, SECURITY-12, SECURITY-14; this increment adds no web service, cloud infrastructure, authentication system, or public endpoint.
- **Blocking findings**: None at requirements stage.

### Resiliency Baseline

- Disabled for this increment by user decision.

### Property-Based Testing

- **Applicable**: PBT-03 for event-matching and customer-inference invariants; PBT-07 domain generators; PBT-08 reproducibility; PBT-09 existing SwiftCheck framework.
- **N/A**: PBT-02 because this increment introduces no new serialization pair at requirements level.
- **Blocking findings**: None at requirements stage.
