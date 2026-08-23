# User Stories — Meeting Completion and Calendar Enrichment

## Scope

- **Persona**: Owner-User.
- **Structure**: User-journey and feature hybrid.
- **Acceptance criteria**: Given/When/Then.

## Epic 1 — Stop Recording Without Blocking

### MCAL-US-1 — Stop and continue working

As the Owner-User, I want recording to stop immediately while final processing continues in the background so that I can keep using the app.

**Acceptance Criteria**

- Given a meeting is recording, when I press Stop, then recording state clears within one second.
- Given final transcription or summary work remains, when I navigate to another meeting or tab, then the app remains responsive.
- Given another meeting needs recording, when a prior meeting is finalizing, then I can start the new recording.

### MCAL-US-2 — See processing status and retry failures

As the Owner-User, I want a passive processing state and retry action so that slow or failed work never looks like a frozen app.

**Acceptance Criteria**

- Given a recording stopped, when final work is pending, then the meeting shows `Finalizing` without opening a modal.
- Given final work completes, then the meeting shows `Ready`.
- Given final work fails, then recorded media remains available and the meeting shows `Needs Attention` with Retry.
- Given the app restarts during finalization, then the incomplete state remains visible and recoverable.

## Epic 2 — Enrich From Calendar

### MCAL-US-3 — Grant minimal Calendar access

As the Owner-User, I want Android Bridge to use calendars already configured on my Mac so that Google Calendar works without another account integration.

**Acceptance Criteria**

- Given Calendar access is undetermined, when enrichment first runs, then macOS requests EventKit calendar permission.
- Given permission is granted, then configured Apple and Google calendars are available read-only.
- Given permission is denied, then meeting processing remains usable and the app offers a System Settings shortcut.
- Given calendar access is used, then Android Bridge requests no Gmail-message or calendar-write permission.

### MCAL-US-4 — Apply one matching event automatically

As the Owner-User, I want one unambiguous overlapping event applied automatically so that title and customer data require no repetitive entry.

**Acceptance Criteria**

- Given exactly one event overlaps the recording, when enrichment runs, then the event snapshot is attached without a custom popup.
- Given I already edited title or customer, when enrichment runs, then my values are not overwritten.
- Given no event overlaps, then the meeting stays editable and usable without calendar metadata.

### MCAL-US-5 — Choose among multiple events or enter data manually

As the Owner-User, I want to choose a matching event or enter meeting data manually when several events overlap so that the correct context is saved.

**Acceptance Criteria**

- Given multiple events overlap, when I open calendar choices, then each candidate shows title, calendar, time, and organizer when available.
- Given a candidate is correct, when I choose it, then its snapshot enriches the meeting.
- Given no candidate is correct, when I choose manual entry, then I can edit title and customer directly.
- Given I choose no event, then calendar ambiguity is dismissed without blocking the meeting.

## Epic 3 — Suggest Customer Conservatively

### MCAL-US-6 — Infer one external customer

As the Owner-User, I want a customer suggested only when participants identify one external organization so that filing is faster without incorrect assumptions.

**Acceptance Criteria**

- Given participant data contains my own address, then that address is excluded.
- Given remaining participants share one non-generic organization domain, then that organization becomes the customer suggestion.
- Given participants use only Gmail, Outlook, Yahoo, or iCloud addresses, then customer remains unset.
- Given several external organizations remain, then customer remains unset for manual entry.

## Epic 4 — File to Second Brain Only on Request

### MCAL-US-7 — Avoid automatic filing prompts

As the Owner-User, I want meeting completion to avoid automatic Second Brain prompts so that finishing a meeting never interrupts my work.

**Acceptance Criteria**

- Given meeting processing completes, then no title/customer/Second Brain sheet opens.
- Given calendar selection is needed, then the meeting shows a passive action rather than a modal.

### MCAL-US-8 — Explicitly add a meeting to Second Brain

As the Owner-User, I want an explicit Add to Second Brain action prefilled from saved metadata so that I control when and where the note is filed.

**Acceptance Criteria**

- Given a meeting is ready, when I invoke Add to Second Brain, then title and customer are prefilled when known.
- Given data needs correction, when I edit it before transfer, then the corrected values are used.
- Given the meeting was already transferred, when I transfer again, then the existing note is updated without an accidental duplicate.
- Given Second Brain transfer fails, then the local meeting remains ready and retryable.

## INVEST Check

- **Independent**: Processing, Calendar access, event selection, customer inference, and filing have discrete outcomes.
- **Negotiable**: UI placement and internal queue details remain implementation decisions.
- **Valuable**: Every story removes friction or prevents data loss/interruption.
- **Estimable**: Each story has bounded behavior and affected components.
- **Small**: Ambiguous matching and filing are separated from recording completion.
- **Testable**: Every story includes observable Given/When/Then criteria.

## Persona Mapping

| Story group | Persona |
|---|---|
| Stop and background processing | Owner-User |
| Calendar permission and matching | Owner-User |
| Customer suggestion | Owner-User |
| Explicit Second Brain transfer | Owner-User |
