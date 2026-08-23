# Meeting Processing Recovery Plan

## Confirmed Root Causes

1. Recent meetings contain persisted transcript segments; the Summary tab's empty state made them look untranscribed.
2. `zai/glm-5.2`, configured for Summarize, returns HTTP 429 because its weekly/monthly quota is exhausted until 2026-08-23.
3. `LLMService.runPi` discards stderr and returns `nil`; finalization then marks the meeting Ready even without a summary.
4. EventKit returned three matching events in the reported UI, so Calendar reads work. Android Bridge is absent from the displayed privacy list because its TCC permission registration must be reset and requested by the installed app identity.

## Steps

- [x] Inspect screenshots, persisted meeting files, app logs, bundle identity, configured providers, and exact pi invocation.
- [x] Add failing regression coverage for missing-summary processing state; confirmed it currently reports `Ready` instead of `Needs Attention`.
- [x] Mark completed finalization/backfill as `Needs Attention` when recorded content exists but summary generation fails.
- [x] Clarify the Summary empty state, point to the persisted Transcript tab, and add `Generate Missing Summary`.
- [x] Request native EventKit access from the installed app at launch and provide an explicit request action/status.
- [x] Switch Summarize from quota-exhausted `zai/glm-5.2` to verified `openai-codex/gpt-5.6-sol`.
- [x] Build, test, sign, install, reset Calendar TCC registration, and relaunch; TCC logged prompt and registration creation for `com.androidbridge.mac`.
- [x] Backfill every missing summary; all 68 transcript-bearing meetings now have the preferred English/Detailed summary, including all four affected August 17 meetings.
- [x] Remove temporary probe files and update audit/build/state records.

## Safety

- Preserve every audio file and transcript.
- Generate only missing summaries; do not overwrite existing summaries.
- Use native EventKit and the existing local pi installation; add no dependency or credential.
