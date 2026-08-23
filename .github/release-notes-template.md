# Android Bridge {{VERSION}}

Source commit: `{{COMMIT}}`
Channel: {{CHANNEL}}

## Install

- **Apple Silicon macOS 13+**: [Download the DMG]({{MACOS_URL}}). Open it, drag the app to Applications, then Control-click the app and choose **Open** the first time.
- **Optional Android 13+ companion**: [Download the release-signed APK]({{ANDROID_URL}}). Android requires normal unknown-source/install consent from the browser or file manager.

> **Mac warning:** This build is not Apple-notarized because the project has no paid Apple Developer account. Do not disable Gatekeeper globally; use Control-click then Open for the normal first launch flow.

## Update notes

This release keeps Mac and Android version metadata aligned from one source version. Update checks use stable releases only and always require platform consent before installation.

Android installations made from the old debug-signed `AndroidBridge-latest.apk` cannot upgrade in place. Uninstall that old copy once, then install this stable APK. Later stable releases use the same release key and preserve app data.

## Checksums and SBOMs

Verify `{{MACOS_CHECKSUM}}` or `{{ANDROID_CHECKSUM}}` before use. CycloneDX SBOMs: `{{MACOS_SBOM}}` and `{{ANDROID_SBOM}}`.
