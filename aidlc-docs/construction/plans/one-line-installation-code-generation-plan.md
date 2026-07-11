# One-Line Installation Code Generation Plan

This file is the single source of truth for this implementation.

## Unit Context

- **Unit**: macOS release installation tooling.
- **User outcome**: Install the latest Android Bridge macOS release with one shell command.
- **Dependencies**: Existing `mac/scripts/make-macos-app.sh`, GitHub Releases, macOS standard command-line tools.
- **Interfaces**: Release archive and matching SHA-256 checksum consumed by the installer.
- **Application boundaries**: No Android, protocol, database, or runtime application logic changes.

## Execution Steps

- [ ] **Step 1 — Installer:** Create `install.sh` using strict shell mode, HTTPS GitHub release resolution, temporary workspace cleanup, SHA-256 verification, archive extraction, and installation into `/Applications/AndroidBridge.app`.
- [ ] **Step 2 — Release packaging:** Create `.github/workflows/release-macos.yml` to build on version tags, package `AndroidBridge.app`, generate its SHA-256 checksum, and publish both assets to GitHub Releases.
- [ ] **Step 3 — Documentation:** Update `README.md` with the canonical one-line macOS installation command, prerequisites, installed path, and scope.
- [ ] **Step 4 — Static validation:** Validate shell syntax, workflow YAML structure, pinned GitHub Action versions, and absence of unsafe installer behavior.
- [ ] **Step 5 — Build/package validation:** Build the macOS bundle, reproduce release archive/checksum generation locally, and verify extraction and checksum compatibility without overwriting the installed application.
- [ ] **Step 6 — Summary:** Create `aidlc-docs/construction/one-line-installation/code/code-generation-summary.md` and update `aidlc-docs/aidlc-state.md`.

## Security Constraints

- SECURITY-10: Pin GitHub Actions to immutable commit SHAs; generate release supply-chain artifacts.
- SECURITY-13: Verify the downloaded archive against its published SHA-256 checksum before extraction or installation.
- SECURITY-15: Fail closed on network, checksum, extraction, and file-operation errors; always remove temporary files.
- Installer input derived from GitHub release metadata must be validated before use.
- No secrets or optional third-party dependencies may be installed.

## Completion Gate

Every step must be completed in sequence and marked `[x]` in the same interaction as its implementation.
