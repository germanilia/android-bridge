# Meeting customer automation requirements

## Intent analysis

- **Request type:** User-facing meeting and calendar enhancement.
- **Scope:** macOS Meetings UI, EventKit matching, local customer metadata, and Second Brain customer selection.
- **Complexity:** Moderate. One local data store, deterministic matching rules, and several existing UI entry points change.
- **Terminology:** Use `Customer` throughout the UI.

## Functional requirements

### MCA-FR-1 Searchable customer picker

- Replace free-text customer assignment with one reusable searchable picker in meeting list editing, meeting detail, calendar resolution, and Second Brain transfer.
- Seed choices from customer names already saved on meetings and client clusters under `work/sela/meetings/`.
- Filter choices case-insensitively while the user types.
- Selecting an existing customer must preserve its canonical spelling.
- A new customer must require an explicit Create New action. Typing alone must not create data.

### MCA-FR-2 Local customer catalog

- Keep a local customer catalog so meeting assignment works when Second Brain is unavailable.
- Creating a customer adds it to the catalog immediately.
- Create the Second Brain client folder only when a meeting is transferred there.
- Customer names are unique case-insensitively and bounded to 200 characters.

### MCA-FR-3 Learned calendar associations

- A selected calendar event may resolve a customer from saved associations based on normalized event title, stable calendar identifier, and external participant organization domains.
- If saved signals resolve to exactly one customer, assign it automatically.
- Without a saved association, auto-assign only an exact case-insensitive inferred-company-to-customer match.
- Fuzzy customer-name matches may be shown as suggestions but must not be assigned automatically.
- If no safe match exists, show the searchable customer picker and remember the confirmed choice.
- Conflicting learned signals must ask instead of guessing.

### MCA-FR-4 Main calendar

- Settings must allow one preferred EventKit calendar, stored by stable calendar identifier.
- Search the preferred calendar first.
- If it has one or more qualifying events, use only those candidates.
- If it has no qualifying events, search all available calendars.
- An unavailable saved calendar must not block fallback matching.

### MCA-FR-5 Tolerant event matching

- Search from 15 minutes before recording start through 15 minutes after recording end.
- Auto-select when exactly one event qualifies after preferred-calendar rules.
- If several events qualify, show the existing event picker ordered by strongest actual overlap, then start-time distance, title, and identifier.
- Ask for customer only after the event is selected.

### MCA-FR-6 Correction and historical meetings

- Settings must list learned customer associations and provide Change and Forget actions.
- New meetings use automation during calendar enrichment.
- Existing meetings use the same rules only when Refresh Calendar Match is selected.
- Never bulk-rewrite historical meetings.

## Non-functional requirements

- Keep EventKit access read-only and local.
- Store the catalog and learned associations locally using atomic JSON writes.
- Do not log customer names, participant addresses, event titles, meeting URLs, or association contents.
- Validate persisted JSON before use and report safe, actionable errors.
- Add no dependency or protocol message.
- Customer lookup and matching must remain deterministic and independently testable.
- Existing meeting media, summaries, and calendar snapshots must remain backward-compatible.

## Acceptance criteria

1. Typing in a customer field filters existing customers and exposes an explicit Create New action.
2. A confirmed unresolved calendar customer is remembered and auto-selected for the next uniquely matching event.
3. Ambiguous or conflicting matches show a picker and never silently select.
4. Preferred-calendar events win; all calendars are searched only when the preferred calendar has no qualifying event.
5. A unique event within the 15-minute tolerance auto-selects.
6. Multiple qualifying events remain user-selectable.
7. Learned associations can be changed or forgotten in Settings.
8. Existing calendar snapshots decode after the schema extension.

## Extension configuration

- Security Baseline remains enabled.
- Resiliency Baseline remains disabled.
- Property-Based Testing remains partial. PBT-02, PBT-03, PBT-07, PBT-08, and PBT-09 apply.
