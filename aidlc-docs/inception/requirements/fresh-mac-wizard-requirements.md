# Fresh Mac Setup Wizard Requirements

## Intent Analysis
- **Request type**: User-facing onboarding feature and installation enhancement.
- **Scope**: macOS application setup UI, dependency detection/install orchestration, permissions guidance, Android APK onboarding, and documentation.
- **Complexity**: Moderate.

## Functional Requirements

### First Launch and Re-entry
1. Show a native setup wizard on first launch when required setup items are incomplete.
2. Keep the wizard available from Settings for later review and repair.
3. Persist only wizard progress that can be revalidated; actual completion status must come from live detection.
4. Allow users to leave and resume setup without losing completed work.

### Dependency Detection
5. Detect Homebrew, ffmpeg, Python/MLX Whisper environment, Ollama, the configured default Ollama model, and pi independently.
6. Mark valid existing installations complete without asking to install them again.
7. Show detected version/path and a clear status for each item.
8. Provide an explicit repair/reinstall action for detected or failed items.
9. Refresh status after each installation attempt and on user request.

### Dependency Installation
10. Ask for separate confirmation before installing each missing third-party dependency.
11. Explain what will be installed, why it is needed, source, approximate download impact when known, and command before confirmation.
12. Install Homebrew first only when the user approves it and a selected dependency requires it.
13. Support installation of ffmpeg, Python/MLX Whisper, Ollama, the default `gemma4:e4b` model, and pi.
14. Stream installation progress and show actionable success/failure output without exposing secrets.
15. Never reinstall, upgrade, or replace a valid dependency without explicit repair/reinstall approval.

### macOS Permissions
16. Guide users through Microphone, Accessibility, Notifications, Local Network, and any other currently required macOS permissions.
17. Detect permission state where macOS APIs permit it and deep-link to the relevant System Settings page where possible.
18. Clearly state when macOS requires manual user action; never claim a permission was granted without verification.

### Android Setup
19. Show a QR code and clickable URL for the rolling `AndroidBridge-latest.apk` artifact.
20. Explain Android's “Install unknown apps” step and that the APK is debug-signed.
21. Guide the user through launching the Android app, granting required permissions, and pairing with the Mac.
22. Verify phone connection before marking Android setup complete.

### Completion
23. Present a final readiness summary separating required, optional, completed, skipped, and failed items.
24. Allow the core app to remain usable when optional AI dependencies are skipped.

## Non-Functional Requirements
1. Native SwiftUI/AppKit experience consistent with the existing Mac app.
2. Installation commands must use fixed allowlisted definitions; no user-controlled shell command construction.
3. External processes must be cancellable where safe, capture stdout/stderr, clean up resources, and fail closed.
4. Downloads and package installation must use official HTTPS sources.
5. The wizard must remain responsive while detection and installations run asynchronously.
6. Status labels and controls must be accessible by keyboard and VoiceOver.
7. No credentials, tokens, or private paths may be logged unnecessarily.
8. Automated tests must cover detection mapping, state transitions, command selection, skip behavior, and failure recovery.

## Out of Scope
- Silently granting macOS or Android permissions.
- Installing an APK onto the phone remotely.
- Apple Developer ID signing/notarization setup.
- Production-signing the Android APK.

## Success Criteria
- A fresh Apple Silicon Mac user can install the app with the one-line command, complete guided setup, install each desired dependency with individual consent, download the phone APK, pair, and reach a verified readiness screen.
- A configured Mac sees existing valid dependencies marked complete and receives no redundant installation prompts.

## Extension Compliance
- **Security Baseline**: Enabled and applicable to process execution, supply-chain sources, integrity, input validation, and fail-safe errors.
- **Resiliency Baseline**: Disabled.
- **Property-Based Testing**: Partial; applicable to pure wizard state transitions and detection-to-status mapping where valuable.
