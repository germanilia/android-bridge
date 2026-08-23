# File Notification Copy Bug Requirements

## Intent Analysis
- **User request**: Make the Mac received-file notification Copy button copy the saved file's absolute path instead of the notification message.
- **Request type**: Bug fix
- **Scope**: Mac notification toast, single component
- **Complexity**: Trivial

## Functional Requirement
When a received-file toast contains an `openFile` action and saved-file `path`, clicking **Copy** must put that exact absolute path on the macOS pasteboard.

Example expected value:

```text
/Users/iliagerman/Library/Caches/AndroidBridge/Received/Screenshot_20260813-194228.png
```

Other toast types must continue copying their visible message text.

## Acceptance Criteria
1. A received-file toast still displays `Click to open <filename>`.
2. Clicking the toast still opens the received file.
3. Clicking **Copy** copies the absolute path from notification metadata, not the visible message.
4. Existing non-file toast Copy behavior remains unchanged.
5. The macOS package builds successfully.

## Non-Functional Requirements
- No new dependency.
- Keep the change local to the Mac toast copy action.
- Do not expose the path anywhere except the local Mac UI and pasteboard after explicit user action.

## Extension Compliance
- **Security Baseline**: Compliant. Local path remains local and is copied only after explicit user action. SECURITY-01 through SECURITY-14 are N/A to this isolated UI behavior; SECURITY-15 remains unchanged.
- **Property-Based Testing (partial)**: PBT-02, PBT-03, PBT-07, and PBT-08 are N/A because no serialization, inverse, data transformation, or domain generator is involved. PBT-09 remains compliant through existing SwiftCheck configuration.
- **Resiliency Baseline**: Disabled; skipped.
