# Direct distribution packaging requirements

## Intent analysis

- **User request**: Prepare the repository so people can install Android Bridge directly on Apple Silicon Macs and optional Android phones without an app marketplace.
- **Request type**: Distribution and update enhancement.
- **Scope estimate**: macOS packaging, Android release signing, GitHub Actions releases, update checks, version metadata, integrity checks, tests, and installation documentation.
- **Complexity estimate**: Moderate. Packaging is straightforward, but stable signing and safe update flows cross Swift, Kotlin, Gradle, shell, and CI boundaries.

## Confirmed decisions

1. Keep the existing native macOS menu-bar and SwiftUI app. Do not replace it with a daemon or browser UI.
2. Support Apple Silicon Macs initially.
3. Publish a DMG containing `AndroidBridge.app` as the primary Mac download.
4. Do not require a CLI installer as the primary user path.
5. No paid Apple Developer Program account is available. The Mac build cannot use Developer ID notarization and must document the first-launch Gatekeeper flow.
6. Publish versioned stable GitHub Releases and retain the rolling `latest-build` prerelease.
7. Keep the Android app optional and support Android 13 and newer.
8. Sign Android release APKs with one dedicated long-lived release key stored outside Git and supplied to GitHub Actions through secrets.
9. Mac updates require user confirmation before download or installation.
10. Android updates may download in-app, but Android's system installation confirmation remains mandatory.
11. Security baseline rules remain enabled. Resiliency and property-based testing extensions are disabled for this increment.

## Platform constraints

- A non-notarized Mac app cannot provide the same warning-free installation as a Developer ID signed and notarized app. The DMG flow must explain Control-click > Open for first launch.
- An ordinary sideloaded Android app cannot install an APK silently. Android must show its package installation confirmation.
- The Android release signing key must remain stable. Losing or changing it prevents in-place upgrades for existing installations.
- macOS update installation must not silently bypass Gatekeeper, change the app's signing identity unexpectedly, or discard user data and privacy grants.

## Functional requirements

### FR-01: Stable and rolling release channels

1. A version tag must create a versioned stable GitHub Release.
2. A push to `main` must continue updating the `latest-build` prerelease.
3. Stable and rolling releases must use the same packaging and validation steps.
4. Public update checks must use stable releases by default and ignore drafts and prereleases.

### FR-02: macOS DMG packaging

1. CI must build the existing `AndroidBridge.app` for Apple Silicon.
2. CI must place the app in a mountable DMG suitable for drag-to-Applications installation.
3. The DMG must use a versioned filename for stable releases and a predictable filename for `latest-build`.
4. CI must validate the app bundle, executable, code signature, DMG mount, and copied app before publication.
5. The existing ZIP may remain only for compatibility if it does not complicate the release pipeline. The DMG is the documented primary package.

### FR-03: macOS direct installation experience

1. README and release notes must provide a direct DMG download link.
2. Instructions must cover download, mount, drag to Applications, and first launch.
3. Instructions must state that the build is not Apple-notarized because no paid Apple Developer account is used.
4. Instructions must show the normal Control-click > Open workflow. They must not instruct users to disable Gatekeeper globally.
5. The existing shell installer may remain as an advanced compatibility path, but it must not be presented as the primary installation method.

### FR-04: Android release APK

1. CI must build `assembleRelease`, not `assembleDebug`, for public Android artifacts.
2. Gradle must read release signing material from environment variables or a temporary CI-only keystore path.
3. Missing signing configuration must fail the release build with a clear error.
4. Signing keys, passwords, and encoded keystore content must never enter Git, build logs, release notes, or artifacts other than the APK signature itself.
5. CI must verify the release APK signature before publication.
6. README and Mac setup UI must link to the stable APK for normal users and identify the phone app as optional.

### FR-05: Version metadata

1. Stable release tags must use semantic versions shaped like `vMAJOR.MINOR.PATCH`.
2. The macOS app version, Android `versionName`, and Android monotonically increasing `versionCode` must be derived from one release version source or checked for exact consistency before publication.
3. The release workflow must reject malformed or inconsistent versions.
4. Update comparisons must use semantic version ordering rather than string ordering.

### FR-06: macOS update check

1. The native Mac app must check the latest stable GitHub Release without blocking startup or normal use.
2. It must compare the installed version with the stable release version.
3. When a newer version exists, it must show the version and ask before downloading.
4. After approval, it must download the DMG and checksum over HTTPS, verify integrity, then open the DMG and show installation guidance.
5. It must not replace the running app silently.
6. Network, metadata, download, checksum, mount, and launch failures must produce a clear user-visible error without changing the installed app.
7. The user must be able to dismiss the prompt and check again later.

### FR-07: Android update check

1. The Android app must check the latest stable GitHub Release without blocking app startup.
2. It must compare the installed `versionCode` or semantic version with the stable APK metadata.
3. When a newer version exists, it must ask before downloading.
4. After approval, it must download the APK and checksum over HTTPS into app-controlled storage.
5. It must verify the checksum and release signing certificate before invoking Android's package installer.
6. Android's mandatory installation confirmation must remain visible to the user.
7. Failed or cancelled updates must preserve the installed app and report the failure or cancellation.
8. Temporary update files must be removed after completion or failure.

### FR-08: Artifact integrity and release contents

Each stable release must publish:

- Apple Silicon macOS DMG.
- DMG SHA-256 checksum.
- Android release APK.
- APK SHA-256 checksum.
- Software Bill of Materials for the macOS and Android production artifacts.
- Release notes containing version, installation links, supported platforms, update notes, and known non-notarized Mac limitations.

The rolling prerelease must publish equivalent artifacts with predictable `latest` names.

### FR-09: Repository setup documentation

1. Maintainer documentation must list required GitHub Actions secrets without their values.
2. It must document how to create, back up, rotate, and restore the Android release keystore safely.
3. It must document the effect of losing or changing the Android signing key.
4. It must document the current self-signed Mac identity setup and the future path to Developer ID signing and notarization.
5. It must document stable release tag creation and rolling prerelease behavior.
6. It must include local validation commands that do not publish releases or expose credentials.

## Non-functional requirements

### NFR-01: Security

- Use HTTPS for GitHub API, release metadata, checksums, DMG, and APK downloads.
- Verify downloaded artifacts before opening or installing them.
- Keep signing secrets out of source control and logs.
- Pin GitHub Actions to immutable commit SHAs.
- Grant workflow permissions only where required.
- Generate SBOMs and run dependency vulnerability checks before stable release publication.
- Fail closed on malformed release metadata, version mismatch, checksum mismatch, signature mismatch, or missing signing configuration.

### NFR-02: Reliability

- Release publication must occur only after all builds and validations pass.
- Updating rolling assets must not leave a mixed set of files from different commits.
- Update failures must leave the currently installed version untouched.
- Downloaded temporary files must be cleaned up.

### NFR-03: Usability

- Normal users must install the Mac app from one DMG download without terminal commands.
- Android installation must use one direct APK link followed by Android's required consent screens.
- The optional Android app must be clearly separated from Mac-only functionality.
- Error messages must tell users what failed and what action is safe to take next.

### NFR-04: Compatibility

- macOS package target: macOS 13 or newer on Apple Silicon.
- Android package target: Android 13 or newer.
- Existing paired-device data, settings, meetings, Second Brain content, and macOS privacy grants must survive upgrades when platform signing constraints permit.

### NFR-05: Maintainability

- Prefer macOS, Android, Gradle, Swift, shell, and GitHub-native mechanisms already used by the repo.
- Do not add an npm package, Homebrew tap, external installer framework, or third-party auto-update framework for this increment.
- Keep release version and asset naming logic centralized and testable.

## Acceptance criteria

1. A tagged CI run produces a stable GitHub Release with a mountable Mac DMG, release-signed APK, checksums, SBOMs, and release notes.
2. A `main` CI run updates the rolling prerelease with equivalent latest artifacts.
3. A clean Apple Silicon Mac can download the DMG, copy the native app to Applications, use Control-click > Open once, and launch it.
4. An Android 13 or newer device can install the direct release APK after normal unknown-source consent.
5. A later APK signed by the same release key upgrades the installed Android app without uninstalling it.
6. Mac and Android apps detect a newer stable release and require user approval before download.
7. Mac verifies the DMG before opening it. Android verifies the APK before showing the system installer.
8. Invalid checksums, signatures, versions, metadata, or missing secrets stop the operation and preserve the installed version.
9. Repository documentation enables a maintainer to configure secrets and publish a stable release without committing sensitive material.

## Out of scope

- Apple App Store, Google Play, F-Droid, or another marketplace.
- Apple Developer ID purchase, notarization, or warning-free Mac installation.
- Intel Mac support.
- Android versions older than 13.
- Silent Android APK installation.
- Silent replacement of the running Mac app.
- npm, Homebrew, MDM, or ADB as the primary public installation channel.
- Replacing the existing native Mac UI with a daemon or browser UI.

## Extension compliance

### Security baseline

- **Applicable and blocking**: SECURITY-06, SECURITY-09, SECURITY-10, SECURITY-12, SECURITY-13, SECURITY-15.
- **Requirements included**: least-privilege workflow permissions, supported toolchains, dependency checks, SBOMs, secret handling, artifact verification, fail-closed behavior, and cleanup.
- **N/A for this increment**: SECURITY-01 through SECURITY-05, SECURITY-07, SECURITY-08, SECURITY-11, and SECURITY-14 because no datastore, external service endpoint, authentication system, cloud network, or public application service is introduced.
- **Current status**: Requirements are compliant. Implementation compliance must be verified before release.

### Resiliency baseline

Disabled by user for this increment.

### Property-based testing

Disabled by user for this distribution-only increment. Example-based version, integrity, packaging, and updater tests remain required.
