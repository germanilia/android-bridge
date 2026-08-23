# DDP2 domain entities

## Boundary

These entities belong to BridgeCore unless explicitly marked as presentation state. They contain no AppKit, SwiftUI, device-link protocol, signing secret, or release-publication behavior.

## SemanticVersion

| Field | Type | Rule |
|---|---|---|
| `major` | non-negative integer | Decimal, no sign, no leading zero unless exactly zero |
| `minor` | integer from 0 through 999 | Same lexical rule |
| `patch` | integer from 0 through 999 | Same lexical rule |

- Canonical text is exactly `MAJOR.MINOR.PATCH`.
- Whitespace, a leading `v`, omitted components, extra components, prerelease/build suffixes, and integer overflow are invalid.
- Ordering compares major, then minor, then patch numerically.
- The stable Release tag is `v` plus canonical text; the manifest uses canonical text without `v`.

## ReleasePlatform

One fixed DDP2 value: `macOSArm64`.

It binds these contract values:

- Minimum operating system: macOS 13.0.
- Architecture: Apple Silicon.
- Manifest descriptor: `macos`.
- Artifact pattern: `AndroidBridge-VERSION-macOS-arm64.dmg`.
- Checksum asset: the artifact name plus `.sha256`.

## GitHubRelease

| Field | Rule |
|---|---|
| Release identity | Returned only by the fixed latest-stable endpoint for `germanilia/android-bridge` |
| `tagName` | Exactly `vMAJOR.MINOR.PATCH` |
| `draft` | Must be `false` |
| `prerelease` | Must be `false` |
| `htmlURL` | HTTPS GitHub URL for the same repository and tag |
| assets | Finite collection with unique names |

Unknown or malformed values invalidate discovery. The client never uses `latest-build` or a caller-supplied repository.

## ReleaseAsset

| Field | Rule |
|---|---|
| `name` | Non-empty, exact expected release filename |
| `browserDownloadURL` | HTTPS URL bound to the fixed repository, release tag, and exact asset name |
| `size` | Positive integer within the supported numeric range |

A stable release must contain exactly one `release-manifest.json`, one canonical versioned Mac DMG, and one corresponding checksum asset. Aliases and Android assets may coexist but are not selected by DDP2.

## ReleaseManifest

The decoder accepts exactly the DDP1 schema-1 keys:

- `schemaVersion`
- `version`
- `versionCode`
- `minimumMacOS`
- `minimumAndroidSdk`
- `macos`
- `android`

Required invariant values:

| Field | Value or rule |
|---|---|
| `schemaVersion` | `1` |
| `version` | Valid canonical semantic version equal to the Release tag without `v` |
| `versionCode` | `major * 1,000,000 + minor * 1,000 + patch` |
| `minimumMacOS` | Exactly `13.0` for schema 1 |
| `minimumAndroidSdk` | Exactly `33` for schema 1 |
| `macos` | Exact Mac artifact descriptor |
| `android` | Structurally valid exact Android descriptor, retained to validate the complete schema |

Extra or missing keys are invalid, including inside descriptors.

## ReleaseArtifact

| Field | Rule |
|---|---|
| `name` | Exact canonical versioned DMG name |
| `size` | Positive byte count equal to the same-named GitHub asset size |
| `sha256` | Exactly 64 lowercase hexadecimal characters |

The Android descriptor additionally carries `signerSha256`; DDP2 validates its schema shape but never uses it to approve a Mac artifact.

## StableReleaseBundle

A validated aggregate containing:

- Stable GitHub Release identity and page URL.
- Parsed semantic version.
- Exact schema-1 manifest.
- Canonical Mac DMG asset.
- Matching Mac checksum asset.

Construction succeeds only after release, manifest, asset, URL, tag, size, and platform invariants agree.

## MacUpdate

| Field | Purpose |
|---|---|
| `currentVersion` | Parsed installed bundle version |
| `availableVersion` | Newer manifest and Release version |
| `releasePageURL` | User-visible GitHub Release page |
| `dmgAsset` | Canonical versioned DMG metadata |
| `checksumAsset` | Exact `.sha256` metadata |
| `expectedSize` | Manifest and GitHub asset byte count |
| `expectedSHA256` | Manifest digest |

A `MacUpdate` is created only when `availableVersion` is greater than `currentVersion`.

## VerifiedMacUpdate

| Field | Rule |
|---|---|
| `fileURL` | Regular DMG file inside an updater-owned unique temporary directory |
| `directoryURL` | Updater-owned temporary directory |
| `version` | Available version approved by the user |
| `size` | Equal to expected size |
| `sha256` | Equal to manifest and checksum digest |

Only this entity may cross from BridgeCore to the AppKit open action.

## UpdateCheckOutcome

- `updateAvailable(MacUpdate)`
- `upToDate(installed: SemanticVersion)`

Discovery failures are typed errors rather than a third successful outcome.

## MacUpdatePresentationState

Presentation-owned mutually exclusive states:

- `idle`
- `checking(manual: Bool)`
- `updateAvailable(MacUpdate)`
- `downloading(MacUpdate, progress)`
- `verified(VerifiedMacUpdate)`
- `opened(VerifiedMacUpdate)`
- `upToDate(SemanticVersion)`
- `failed(UpdateFailurePresentation)`

`lastAutomaticFailure` may accompany `idle` for Settings status without producing an unsolicited launch dialog.

## UpdateFailure

Typed failure groups:

- `invalidInstalledVersion`
- `networkUnavailable`
- `unexpectedHTTPStatus`
- `untrustedURL`
- `invalidRelease`
- `invalidManifest`
- `unsupportedPlatform`
- `missingAsset`
- `duplicateAsset`
- `checksumMetadataMismatch`
- `downloadTooLarge`
- `downloadSizeMismatch`
- `downloadDigestMismatch`
- `cancelled`
- `temporaryStorageFailure`
- `openFailed`

Errors carry safe diagnostics only. They never include response bodies, URL credentials, local user content, or signing material.

## Entity relationships

1. `GitHubRelease` and its manifest asset produce a validated `StableReleaseBundle`.
2. `StableReleaseBundle` plus installed `SemanticVersion` produces either `MacUpdate` or `upToDate`.
3. User consent plus `MacUpdate` starts checksum and DMG retrieval.
4. Successful size and digest validation produces `VerifiedMacUpdate`.
5. Only `VerifiedMacUpdate` can be opened by the presentation layer.
