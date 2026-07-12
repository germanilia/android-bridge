# Live Transcription Fix — Code Generation Plan

## Context

Mac meeting recording already rotates audio every 30 seconds and submits each completed chunk to a serial transcription queue. The observed placeholder transcript proves live processing ran but Whisper returned no result. This increment will expose and fix the actual local-tool failure without moving transcription to meeting end.

## Execution Plan

- [x] Step 1: Reproduce the Whisper invocation against a saved meeting chunk and identify the concrete failure.
- [x] Step 2: Fix the smallest confirmed issue in the live chunk transcription path or local Whisper setup.
- [x] Step 3: Add focused tests covering live chunk submission and transcription failure reporting where practical. Existing setup/tool detection tests cover the confirmed deployment issue; no speculative test seam added.
- [x] Step 4: Run Mac tests and build the macOS application.
- [x] Step 5: Remove temporary debugging artifacts and document verification results.

## Verification

- `cd mac && swift test`: 19 tests passed plus 100 property checks.
- `cd mac && ./scripts/make-macos-app.sh`: built, installed, and relaunched `/Applications/AndroidBridge.app`.
- Bundled Whisper smoke test against a saved 30-second meeting chunk: passed and produced transcript output.
- Temporary debug files and markers: removed.

## Scope

- Application code: `mac/Sources/BridgeCore/`
- Tests: `mac/Tests/BridgeCoreTests/`
- No new dependency unless the existing local Whisper installation is proven unusable.
- Preserve the current 30-second live chunk model; stop only flushes the final chunk.

## Extension Compliance

- Security Baseline: applicable file/process boundaries remain local; no secrets or user audio will be logged.
- Resiliency Baseline: disabled.
- Property-Based Testing: N/A; this is process integration, not a pure transformation or serialization change.
