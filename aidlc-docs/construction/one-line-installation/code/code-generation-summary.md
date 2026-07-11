# One-Line Installation Code Generation Summary

## Created
- `install.sh` — public macOS installer with HTTPS-only downloads, release-tag validation, SHA-256 verification, temporary-file cleanup, replacement installation, and fail-fast errors.
- `.github/workflows/release-macos.yml` — every push to `main` builds the macOS app and debug-signed Android APK, generates checksums, and replaces assets in the rolling `latest-build` prerelease.

## Modified
- `README.md` — canonical one-line installation command, direct APK download, and rolling artifact behavior.
- `install.sh` now installs from the rolling `latest-build` release rather than stable version tags.

## Validation Performed
- `bash -n install.sh`
- Ruby YAML parse for `.github/workflows/release-macos.yml`
- Confirmed GitHub Action uses an immutable commit SHA.
- `NO_INSTALL=1 mac/scripts/make-macos-app.sh`
- Created and verified `AndroidBridge-macOS-arm64.zip` and its SHA-256 checksum.
- Extracted the archive and confirmed its executable exists.
- Verified the application bundle signature.
- Built `:app:assembleDebug`, confirmed debug signing, and verified the APK checksum.

## Security Compliance
- **SECURITY-10**: Compliant — action pinned to an immutable SHA; macOS and APK checksums published; existing dependency lock files retained.
- **SECURITY-13**: Compliant — installer validates SHA-256 before extraction and installation.
- **SECURITY-15**: Compliant — strict shell mode, explicit network failure handling, fail-closed verification, and temporary resource cleanup.
- **SECURITY-01 through SECURITY-09, SECURITY-11, SECURITY-12, SECURITY-14**: N/A — no datastore, web/API endpoint, authentication system, network intermediary, cloud policy, or deployed service introduced.

No blocking security findings.
