# pi Model Selector Code Generation Plan

Single source of truth for this increment. Approved by user instruction: "just do it".

## Context

- Existing Mac `BridgeCore` and SwiftUI settings only.
- No new dependencies, services, schemas, or infrastructure.
- Requirements: `aidlc-docs/inception/requirements/pi-model-selector-requirements.md`.

## Steps

- [x] Step 1: Add failing tests in `mac/Tests/BridgeCoreTests/CoreTests.swift` for pi model output parsing and missing-summary eligibility.
- [x] Step 2: Implement pi model discovery and parsing in `mac/Sources/BridgeCore/MeetingCapture.swift`.
- [x] Step 3: Implement non-overwriting missing-summary backfill in `mac/Sources/BridgeCore/MeetingCapture.swift` and expose it through `mac/Sources/BridgeCore/LinkManager.swift`.
- [x] Step 4: Replace hard-coded models and add loading/error/backfill UI in `mac/Sources/BridgeApp/BridgeApp.swift`.
- [x] Step 5: Run `swift test` and `swift build` in `mac/`.
- [x] Step 6: Write code summary and update AI-DLC state.
