# Meeting Processing Recovery Summary — 2026-08-17

## Root Cause

- All four reported August 17 meetings had complete persisted transcript segments.
- Their summaries were absent because the configured Summarize model, `zai/glm-5.2`, returned HTTP 429: weekly/monthly quota exhausted until 2026-08-23.
- `LLMService` returned `nil` for that provider failure, while finalization still presented the meeting as `Ready`.
- The Summary tab's generic live-recording placeholder made a completed transcript look missing.
- Calendar matching had already returned three real overlapping events, proving EventKit reads worked. The installed identity nevertheless needed a clean TCC registration to appear reliably in Calendar privacy controls.

## Corrections

- Missing-summary finalization/backfill now persists `Needs Attention` rather than false `Ready`.
- Summary regeneration sets `Finalizing`, then `Ready` or `Needs Attention` from the actual persisted outcome.
- Empty Summary UI now distinguishes active recording, absent transcription, and provider failure; it links the user to the Transcript tab and offers `Generate Missing Summary`.
- The app requests EventKit full access at launch, shows authorization status, and includes an explicit `Request Calendar Access` action.
- Replaced an unavailable Calendar SF Symbol with the supported `calendar` symbol.
- Summarize model changed to verified `openai-codex/gpt-5.6-sol`.

## Recovery Result

- 68 meetings contain persisted transcripts.
- 68 of 68 now contain the preferred `summary-English-Detailed.md`.
- Four affected August 17 meetings were backfilled and remain `Ready` with 6, 56, 115, and 174 transcript segments.
- No media or transcript was deleted or overwritten.

## Validation

- `swift test`: 31 XCTest cases passed; both SwiftCheck properties passed 100 cases.
- `swift build`: passed.
- `swift run MacCheck`: 14/14 passed.
- `git diff --check`: passed.
- Release app signed, installed, and relaunched.
- Built/installed executable SHA-256: `32209cd933b0086347896b22abd7368a286030ffc0c04091c09a48cf68106f49`.
- Calendar TCC log confirms prompt plus registration creation for `com.androidbridge.mac`.
