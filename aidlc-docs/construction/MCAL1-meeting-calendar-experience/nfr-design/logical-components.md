# Logical Components — MCAL1

- **Calendar Domain**: Codable snapshots, overlap matcher, customer inference.
- **EventKit Adapter**: Authorization and bounded event fetch.
- **Meeting State Persistence**: End time, processing state, selected event snapshot.
- **Finalization Queue**: Existing serial transcription/finalization ordering.
- **Calendar Candidate State**: Transient published candidates and status messages.
- **Meetings UI State**: Inline processing label, event menu, manual edit, retry/settings actions.

No queue service, cache, database, backend, or cloud infrastructure is added.
