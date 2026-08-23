# Direct distribution packaging components

## Scope

These components add release packaging and user-confirmed updates without changing the device-link protocol or replacing either native application shell.

## Shared release components

### Version source

**Location**: root `VERSION`.

**Responsibilities**:

- Hold one strict `MAJOR.MINOR.PATCH` value without a leading `v`.
- Supply macOS `CFBundleShortVersionString`, Android `versionName`, and release asset names.
- Derive Android `versionCode` as `major * 1_000_000 + minor * 1_000 + patch` after validating each minor and patch component is at most 999 and the result is within Android's supported range.
- Require a stable tag to equal `v` plus the file value.

### Release manifest

**Artifact**: `release-manifest.json`.

**Responsibilities**:

- Describe one immutable stable or rolling artifact set.
- Carry schema version, semantic version, Android version code, minimum supported platforms, asset names, byte sizes, SHA-256 digests, and Android signer certificate SHA-256 fingerprint.
- Never carry credentials or local paths.
- Use asset names that must match assets in the same GitHub Release.

### Release packaging scripts

**Responsibilities**:

- Validate version input and event/tag consistency.
- Build or package `AndroidBridge.app` as an Apple Silicon DMG.
- stage the signed Android release APK.
- Calculate checksums and sizes.
- Read the public APK signing fingerprint from the signed APK.
- Generate and validate the manifest.
- Validate the mounted DMG, copied app, app architecture, app signature, APK signature, checksums, and manifest-to-file consistency.

### GitHub release workflow

**Location**: `.github/workflows/release-macos.yml`.

**Responsibilities**:

- Run on `main` pushes and semantic version tags.
- Use the same build and validation path for stable and rolling channels.
- Materialize signing credentials only in temporary runner locations.
- Generate SBOMs and execute vulnerability scans before publication.
- Publish a complete artifact set only after all validations pass.
- Use versioned stable names and predictable rolling names.

## macOS update components

### `SemanticVersion`

**Layer**: BridgeCore.

**Responsibilities**:

- Strictly parse three non-negative decimal components.
- Compare versions numerically.
- Reject prefixes, suffixes, missing components, negatives, and overflow.

### `ReleaseManifest` and `ReleaseArtifact`

**Layer**: BridgeCore.

**Responsibilities**:

- Decode the shared JSON schema.
- Reject unsupported schema versions, malformed versions, invalid SHA-256 values, unexpected platform constraints, non-positive sizes, and missing asset metadata.

### `GitHubReleaseClient`

**Layer**: BridgeCore.

**Responsibilities**:

- Fetch `https://api.github.com/repos/germanilia/android-bridge/releases/latest` with `URLSession`.
- Select `release-manifest.json` from the stable release assets.
- Reject drafts, prereleases, non-HTTPS URLs, unexpected hosts, duplicate required assets, and metadata that does not match the release tag.

### `MacUpdateService`

**Layer**: BridgeCore.

**Responsibilities**:

- Compare the installed bundle version with the validated stable manifest.
- Return no update when current is equal or newer.
- Download the selected DMG into a unique temporary directory only after consent.
- Enforce expected size and SHA-256 before returning a local URL.
- Remove partial or untrusted files on failure.

### `MacUpdateController`

**Layer**: BridgeApp.

**Responsibilities**:

- Start one non-blocking check after launch.
- Expose a manual Settings check.
- Present native update confirmation and clear errors on the main actor.
- Ask `MacUpdateService` to download only after confirmation.
- Open the verified DMG with `NSWorkspace` and display drag-to-Applications guidance.
- Never replace or terminate the running app.

## Android update components

### `SemanticVersion`

**Layer**: Android app core.

**Responsibilities**:

- Implement the same strict parser and ordering rules as the Swift type.

### `ReleaseManifest` and platform artifact models

**Layer**: Android app core.

**Responsibilities**:

- Decode and validate the shared manifest with kotlinx serialization.
- Select Android metadata and reject invalid versions, sizes, digests, constraints, or signer fingerprints.

### `GitHubReleaseClient`

**Layer**: Android app core.

**Responsibilities**:

- Fetch only the latest stable GitHub Release and its manifest over HTTPS.
- Apply repository, host, stable-release, tag, and required-asset validation equivalent to the Mac client.

### `AndroidUpdateService`

**Layer**: Android app core.

**Responsibilities**:

- Compare the installed `BuildConfig.VERSION_NAME` and `VERSION_CODE` with the manifest.
- Download the APK into a unique application cache directory only after consent.
- Enforce byte size and SHA-256.
- Delegate certificate continuity validation to `ApkSignatureVerifier`.
- Remove partial or rejected files.

### `ApkSignatureVerifier`

**Layer**: Android platform integration.

**Responsibilities**:

- Read the installed package signing certificate with `PackageManager`.
- Read the downloaded archive's signing certificate.
- Require exactly the expected signer continuity and require its SHA-256 fingerprint to match the manifest.
- Fail closed if certificate metadata is unavailable or ambiguous.

### `ApkInstaller`

**Layer**: Android platform integration.

**Responsibilities**:

- Convert the verified cache file to a scoped `FileProvider` content URI.
- Launch Android's package installer with read permission.
- Preserve Android's mandatory unknown-source and installation confirmation screens.
- Never request device-owner or silent-install privileges.

### Android update UI

**Layer**: `MainActivity` and Compose UI.

**Responsibilities**:

- Run one lifecycle-owned asynchronous launch check.
- Add a Settings tab containing current version and manual check action.
- Present update, progress, completion, cancellation, and error states.
- Start downloading only after explicit confirmation.
- Delete stale update cache on app startup.

## Documentation components

### Public installation guide

- Make DMG drag installation primary.
- Explain Control-click then Open without recommending global Gatekeeper disablement.
- Link the stable release APK and mark Android optional.

### Maintainer release guide

- List secret names only.
- Document Android keystore generation, backup, restoration, and continuity risk.
- Document local validation and stable tag procedure.
- Explain the current self-signed Mac identity and future notarization path.
