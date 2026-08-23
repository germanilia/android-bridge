# pi Model Selector and Summary Backfill Code Summary

## Modified application files

- `mac/Sources/BridgeCore/MeetingCapture.swift`
  - Parses `pi --list-models` output into `provider/model` identifiers.
  - Loads models using the configured pi executable.
  - Backfills only meetings with transcripts and no summary for the active language/type.
  - Preserves existing summary files and reports attempted/completed counts.
- `mac/Sources/BridgeCore/LinkManager.swift`
  - Runs backfill off the main thread.
  - Publishes running and completion/failure status.
- `mac/Sources/BridgeApp/BridgeApp.swift`
  - Removes the hard-coded pi model list.
  - Shows locally available models, refresh/loading state, and discovery errors.
  - Adds **Backfill Missing Summaries** to the Summarize row.
- `mac/Tests/BridgeCoreTests/CoreTests.swift`
  - Tests pi model parsing.
  - Tests missing-summary generation and existing-summary preservation.

## Verification

- `cd mac && swift test`: 21 tests passed.
- `cd mac && swift build`: passed.
- Existing unrelated Swift warnings remain in `LinkManager.swift` for deprecated Security API and CoreAudio pointer handling.

## Extension compliance

- **Security Baseline**: Compliant. No credentials added, persisted, or logged. Transcripts use the explicitly selected provider.
- **Resiliency Baseline**: N/A; disabled.
- **Property-Based Testing**: N/A; no enabled round-trip or general invariant introduced.
