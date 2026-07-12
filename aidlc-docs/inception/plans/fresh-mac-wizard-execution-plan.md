# Fresh Mac Setup Wizard Execution Plan

## Scope
Native first-launch macOS setup wizard with reusable Settings entry, dependency detection and consent, permission guidance, Android APK onboarding, and readiness verification.

## Risk
- **Level**: Medium
- **Primary risks**: external process execution, third-party package installation, macOS permission limitations, long-running UI work.
- **Controls**: fixed allowlisted commands, per-item confirmation, background execution, live re-detection, explicit repair actions, official HTTPS sources.

## Stage Decisions
- [x] Requirements Analysis — completed and approved.
- [x] User Stories — included implicitly through the approved end-to-end fresh-Mac setup journey; separate story artifacts skipped at user direction.
- [x] Workflow Planning — completed autonomously per user instruction.
- [x] Application Design — executed minimally in implementation boundaries: `SetupCatalog`, `SetupDetector`, `SetupWizardModel`, and `SetupWizardView`.
- [x] Units Generation — skipped; one cohesive Mac onboarding unit.
- [x] Functional Design — executed minimally through dependency states and wizard pages.
- [x] NFR Requirements/Design — security, responsiveness, accessibility, and failure behavior incorporated directly.
- [x] Infrastructure Design — skipped; no infrastructure change.
- [x] Code Generation — completed.
- [x] Build and Test — completed.

## Implementation Sequence
1. Add pure setup dependency catalog, states, and live detector to BridgeCore.
2. Add first-launch SwiftUI wizard and Settings re-entry.
3. Add per-dependency confirmation, asynchronous command execution, cancellation, output, repair, and refresh.
4. Add permission guidance and Android APK QR/download/pairing status.
5. Point Whisper runtime at the wizard-managed Application Support environment.
6. Add catalog tests, README documentation, build/test/package/launch validation.

## Success Criteria
- Missing and installed dependencies display correctly without redundant prompts.
- Every installation requires its own confirmation.
- Wizard can be resumed from Settings.
- APK onboarding and phone readiness are visible.
- Mac app builds, tests pass, release bundle launches, and first-launch sheet appears.
