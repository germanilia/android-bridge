# One-Line macOS Installation Requirements

## Intent Analysis
- **User request**: Create a one-line installation command for Android Bridge.
- **Request type**: Distribution enhancement.
- **Scope estimate**: Repository release tooling, installer script, and installation documentation.
- **Complexity estimate**: Simple.

## Functional Requirements
1. Provide a public command shaped like `curl -fsSL <installer-url> | bash`.
2. Install only the macOS application.
3. Download the application artifact from this repository's GitHub Releases.
4. Install `AndroidBridge.app` into `/Applications`.
5. Replace an existing Android Bridge installation cleanly.
6. Verify the downloaded release before installation using a published checksum.
7. Return a non-zero exit status and a clear error when download, verification, extraction, or installation fails.

## Non-Functional Requirements
1. Use standard macOS command-line tools where practical; add no installer framework dependency.
2. Require explicit elevation only when `/Applications` is not writable.
3. Use HTTPS for release and installer downloads.
4. Avoid installing optional dependencies such as Ollama, pi, ffmpeg, or MLX Whisper.
5. Support Apple Silicon Macs running the project's documented minimum macOS version.
6. Keep the installer non-interactive except for a macOS privilege prompt when required.

## Release Requirements
1. GitHub Releases must contain a packaged, signed macOS application artifact and checksum.
2. The installer should resolve the latest release by default.
3. README installation documentation must show the canonical command and explain what it changes.

## Out of Scope
- Android APK installation.
- Homebrew Cask distribution.
- Building the application from source on the user's machine.
- Installing optional transcription or LLM dependencies.

## Extension Compliance
- **Security Baseline**: Applicable. HTTPS, checksum verification, and fail-fast behavior are required.
- **Resiliency Baseline**: Disabled.
- **Property-Based Testing**: Not applicable; installer behavior is better covered by shell/static and smoke checks.
