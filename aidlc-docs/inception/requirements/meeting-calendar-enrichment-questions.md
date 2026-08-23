# Meeting Completion and Calendar Enrichment Questions

Answer each question by placing the option letter after its `[Answer]:` tag. Choose the final `Other` option when needed and add the custom answer after the tag.

## Question 1
How should Android Bridge access calendar events?

A) Use native macOS EventKit and the calendar accounts already configured in Apple Calendar, including Google accounts (recommended; no custom Google OAuth or backend)

B) Connect directly to Google Calendar through Google OAuth and the Google Calendar API

C) Support both native EventKit and direct Google Calendar API connections

D) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 2
How should a recording be matched to a calendar event?

A) Automatically match the event overlapping the recording time; if multiple events match, show a picker only when the user requests calendar details

B) Match the event with the nearest start time within 30 minutes

C) Always require the user to select an event manually

D) Other (please describe after [Answer]: tag below)

[Answer]: D — Automatically match overlapping events. When multiple events match, present those events plus a manual-entry option.

## Question 3
How should the customer be inferred from participants?

A) Exclude the user's own addresses, group external attendees by email domain/company, use the single external company when unambiguous, and leave customer unset when ambiguous (recommended)

B) Use the organizer's company or email domain

C) Infer the customer only from the event title

D) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 4
Does Android Bridge need access to Gmail messages, or only calendar events belonging to a Google account?

A) Calendar events only; no Gmail message access (recommended)

B) Calendar events plus related Gmail messages

C) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 5
When should calendar enrichment and Second Brain filing happen?

A) Enrich meeting metadata automatically after recording, without a popup; file to Second Brain only when the user presses an explicit action (recommended)

B) Perform both calendar enrichment and Second Brain filing only after an explicit user action

C) Enrich and file automatically without showing a popup

D) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 6
What should happen when recording stops while transcription or summary work is still running?

A) Stop recording immediately, let the user continue, process remaining work in the background, and show non-blocking progress with retry (recommended)

B) Keep the current blocking completion flow but add a cancel action

C) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 7
Should security extension rules remain enforced for this increment?

A) Yes — enforce all SECURITY rules as blocking constraints (current project setting)

B) No — disable SECURITY rules for this increment

C) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 8
Should the resiliency baseline be applied to this increment?

A) Yes — apply the resiliency baseline as directional design-time guidance

B) No — skip the resiliency baseline (current project setting)

C) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 9
Should property-based testing rules remain partially enforced for this increment?

A) Yes — enforce all PBT rules

B) Partial — enforce round trips, invariants, generator quality, reproducibility, and framework selection (current project setting)

C) No — skip PBT rules for this increment

D) Other (please describe after [Answer]: tag below)

[Answer]: B
