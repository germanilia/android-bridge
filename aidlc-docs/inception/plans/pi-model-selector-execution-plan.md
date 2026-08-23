# pi Model Selector and Summary Backfill Execution Plan

## Analysis

- **Change type**: Existing Mac settings and meeting-summary behavior
- **Affected components**: `BridgeCore` model discovery, `MeetingStore` backfill, SwiftUI settings
- **Risk**: Low
- **Dependencies**: None added
- **Rollback**: Revert isolated Swift changes

## Stage decisions

- [x] Requirements Analysis — completed
- [x] User Stories — skipped; small bug fix/enhancement with one owner-user
- [x] Application Design — skipped; existing component boundaries suffice
- [x] Units Generation — skipped; one straightforward Mac increment
- [x] Functional Design — skipped; simple parsing and filtering behavior
- [x] NFR Requirements — skipped; existing local process and privacy constraints suffice
- [x] NFR Design — skipped
- [x] Infrastructure Design — skipped; no infrastructure change
- [ ] Code Generation — execute
- [ ] Build and Test — execute

## Code-generation sequence

- [ ] Add failing Swift tests for pi model-list parsing and missing-summary detection.
- [ ] Add a `BridgeCore` pi model discovery implementation using the configured pi executable and `--list-models`.
- [ ] Replace the hard-coded SwiftUI model list with discovered local models and visible loading/error state.
- [ ] Add missing-summary backfill in `MeetingStore` without overwriting existing summaries.
- [ ] Add **Backfill Missing Summaries** button and progress/result state for Summarize settings.
- [ ] Run Mac tests and build.

## Success criteria

- Picker shows locally available `provider/model` identifiers, including authenticated `openai-codex/*` models.
- Discovery failure is visible and does not show a stale hard-coded list.
- Backfill runs only from its button, processes transcript-bearing meetings with missing summaries, and preserves existing summaries.
- Mac tests and build pass.

## Extension compliance

- **Security Baseline**: Compliant; no credentials persisted or logged, no new network surface.
- **Resiliency Baseline**: N/A; disabled.
- **Property-Based Testing**: N/A; no enabled round-trip or invariant property introduced.
