# Fresh Mac Setup Wizard Summary

## Implemented
- Native first-launch setup wizard with reusable Settings entry.
- Live detection for Homebrew, ffmpeg, Python, bundled or managed MLX Whisper, Ollama, `gemma4:e4b`, Node.js, and pi.
- Per-dependency confirmation, background installation, output, cancellation, refresh, and repair actions.
- Live macOS permission checks and deliberate request/settings actions.
- Android APK QR code, download guidance, and phone connection readiness.
- Whisper runtime fallback to the wizard-managed Application Support environment.
- Stable macOS signing identity imported by GitHub Actions so TCC permissions survive rolling app updates.
- Automatic meeting detection no longer triggers Screen Recording permission dialogs.

## Validation
- `swift test`: 19 XCTest tests plus 100 SwiftCheck cases passed.
- Release app built and signed with `Android Bridge Distribution`.
- Installed app launched with the setup wizard sheet.
- Bundled MLX Whisper detection regression test passed.

## Permission Migration
The previous rolling CI artifacts were ad-hoc signed, so macOS treated each changed build as a different security identity. The new stable signing identity fixes future updates. Existing Screen Recording and Microphone grants must be granted once to the new identity; after that, updates signed with the same identity retain them.

## Security Compliance
- SECURITY-05: fixed allowlisted dependency definitions; no user-provided commands.
- SECURITY-10: signing material stored in GitHub encrypted secrets and action pinned by commit SHA.
- SECURITY-13: stable artifact identity plus existing checksums.
- SECURITY-15: process failures are visible and fail closed; automatic permission prompts removed.
- Other baseline rules: N/A to this local setup feature.
