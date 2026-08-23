# Frontend Components — MCAL1

## ProcessingStatusLabel

Displays compact semantic state: Recording, Finalizing, Ready, or Needs Attention. Finalizing is passive; Needs Attention exposes Retry.

## MeetingCalendarSection

Inline section inside selected meeting detail:

- Attached event summary when selected.
- `Find Calendar Event` action when no event is attached.
- Multiple candidates as native menu choices.
- `Enter manually` switches existing title/customer controls into edit mode.
- `No calendar event` dismisses candidates.
- Permission/fetch message with Retry and Calendar Settings actions.

## Existing Second Brain Action

Remains meeting-level and explicit. Prefills current customer. No automatic sheet.

## Interaction Rules

- Native SwiftUI controls and keyboard behavior.
- No full-window overlay or modal on completion.
- State and actions remain visible without preventing navigation.
- Color is supplementary; every state has text and icon.
