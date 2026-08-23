# NFR Requirements — MCAL1

## Responsiveness

- Stop-state UI update within one second.
- No Whisper, LLM, EventKit query, filesystem finalization, or Second Brain subprocess on main/network receive paths.
- Candidate rendering remains bounded to the overlap query window.

## Reliability

- Retain raw media/transcript on all finalization and enrichment failures.
- Persist state and selected event snapshot atomically where Foundation permits.
- Detect interrupted finalization at next launch and expose retry.
- Preserve chunk-before-finalize ordering.

## Privacy and Security

- EventKit event-read access only; no Gmail or calendar write scopes.
- No participant, event URL, customer, transcript, or private path content in logs.
- Calendar strings are untrusted local external input and use existing sanitization before path/Second Brain operations.
- Permission denial fails closed for calendar access and does not degrade unrelated meeting behavior.

## Maintainability

- EventKit stays behind one adapter.
- Matching/customer inference remain pure.
- No third-party dependency added.
- Existing meeting folders remain readable without migration.

## Usability

- No custom modal on completion.
- Every state includes text, not color alone.
- Multiple candidates include manual and no-event options.

## Testability

- XCTest examples cover matching, inference, persistence, and recovery.
- SwiftCheck verifies overlap/order invariants with shrinking and reproducible seeds.

## Compliance

- Security applicable: SECURITY-01, SECURITY-03, SECURITY-05, SECURITY-11, SECURITY-13, SECURITY-15.
- Security N/A: cloud/web/auth-specific rules.
- Partial PBT applicable: PBT-03, PBT-07, PBT-08, PBT-09.
- Blocking findings: none.
