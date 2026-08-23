# DDP1 domain entities

## `SemanticVersion`

| Field | Type | Constraint |
|---|---|---|
| `major` | Non-negative integer | Must permit derived code within Android maximum |
| `minor` | Integer | 0 through 999 |
| `patch` | Integer | 0 through 999 |

Derived values:

- `text`: `major.minor.patch`.
- `tag`: `v` plus `text`.
- `androidVersionCode`: `major * 1,000,000 + minor * 1,000 + patch`.

Identity is all three numeric components. Ordering is numeric major, then minor, then patch.

## `ReleaseChannel`

Values:

- `stable(version, tag)`.
- `rolling(commitSHA)`.

Derived properties:

| Property | Stable | Rolling |
|---|---|---|
| Label | Semantic version text | `latest` |
| GitHub public tag | Matching semantic tag | `latest-build` |
| Draft staging tag | None | `latest-build-{commitSHA}` |
| Prerelease | False | True |
| May overwrite | Never | Only through staged replacement transaction |

## `ArtifactDescriptor`

| Field | Type | Constraint |
|---|---|---|
| `platform` | `macos` or `android` | Required |
| `name` | Basename string | Exact channel naming rule |
| `size` | Positive integer | Must equal file bytes |
| `sha256` | Hex string | 64 lowercase characters |
| `sbomName` | Basename string | Exact channel naming rule |

Android adds `signerSha256`, a normalized 64-character certificate digest.

## `ReleaseManifest`

| Field | Type | Constraint |
|---|---|---|
| `schemaVersion` | Integer | Exactly 1 |
| `version` | Semantic-version text | Equals root source and stable tag when stable |
| `versionCode` | Positive integer | Equals derived Android code |
| `minimumMacOS` | Version text | `13.0` |
| `minimumAndroidSdk` | Integer | 33 |
| `macos` | Artifact descriptor | DMG descriptor |
| `android` | Android artifact descriptor | APK descriptor plus signer |

The manifest is immutable after publication and identifies artifacts by name, not embedded URL.

## `SigningInputs`

### Mac

| Field | Classification | Persistence |
|---|---|---|
| PKCS#12 bytes | Secret | Temporary runner file only |
| Import password | Secret | Masked process environment only |
| Identity selector | Public configuration | Workflow/script input |
| Expected designated requirement | Public trust metadata | Checked-in file |

### Android

| Field | Classification | Persistence |
|---|---|---|
| Keystore bytes | Secret | Temporary runner file only |
| Store password | Secret | Masked process environment only |
| Key password | Secret | Masked process environment only |
| Alias | Sensitive configuration | Secret-backed environment |
| Signer fingerprint | Public trust metadata | Generated into manifest and validation output |

Secret-bearing entities never enter release metadata.

## `MacApplicationBundle`

| Field | Source | Validation |
|---|---|---|
| Path | Build output | Existing directory with expected bundle layout |
| Bundle identifier | Info.plist | `com.androidbridge.mac` |
| Short version | Info.plist | Semantic source value |
| Bundle version | Info.plist | Derived numeric code |
| Architecture | Executable inspection | arm64 |
| Signature | `codesign` | Deep strict verification succeeds |
| Designated requirement | `codesign` | Equals checked-in expected value |

## `AndroidPackage`

| Field | Source | Validation |
|---|---|---|
| Path | Gradle release output | Existing non-empty APK |
| Application ID | APK metadata | `com.androidbridge` |
| Version name | APK metadata | Semantic source value |
| Version code | APK metadata | Derived numeric code |
| Minimum SDK | APK metadata | 33 |
| Signature | Android signing tool | Verification succeeds |
| Signer SHA-256 | Signing certificate | Exactly one normalized digest |

## `DiskImage`

| Field | Constraint |
|---|---|
| Format | Compressed read-only DMG |
| Root app | Signed `AndroidBridge.app` |
| Root convenience link | `Applications` symlink to `/Applications` |
| Extra root entries | None |
| Mounted app | Must repeat all `MacApplicationBundle` validations |

## `SoftwareBillOfMaterials`

| Field | Constraint |
|---|---|
| Format | CycloneDX JSON |
| Subject | One production DMG or APK artifact |
| Filename | Channel-specific `.cdx.json` name |
| Tool identity | Pinned tool name and version recorded in metadata |
| Components | Production dependencies discovered from package and lock inputs |

## `VulnerabilityFinding`

| Field | Constraint |
|---|---|
| Identifier | Scanner advisory/CVE/OSV identifier |
| Component | Affected package and version |
| Severity | Scanner-normalized severity |
| Fixed version | Included when known |
| Source | Scanner/database identity |

High and critical findings block unless a valid pre-existing exception applies.

## `SecurityException`

| Field | Constraint |
|---|---|
| Finding identifier | Exact finding |
| Component | Exact package/version range |
| Rationale | Non-empty |
| Owner | Named maintainer |
| Expires | Future date at publication time |
| Compensating control | Non-empty and testable |

An exception cannot apply to signing, checksum, signer, manifest, or publication-integrity failures.

## `ReleaseSet`

Contains:

- One `ReleaseChannel`.
- One `SemanticVersion`.
- One DMG descriptor and file.
- One APK descriptor and file.
- Two checksum files.
- Two SBOM files.
- One release manifest.
- One release-notes document.
- One source commit SHA.
- For stable only, byte-identical predictable DMG/APK aliases and their checksum files for direct latest-release links.

A set is either incomplete or validated. Only validated sets are publishable. Stable aliases are validated against their canonical artifact bytes but are not referenced by the manifest.

## `RollingPromotion`

| Field | Meaning |
|---|---|
| `stagingTag` | Commit-specific draft tag |
| `publicTag` | `latest-build` |
| `previousTag` | `latest-build-previous` |
| `state` | created, uploaded, verified, previousMoved, promoted, published, remoteVerified, rolledBack |

Allowed transitions are linear except any state before `previousMoved` may abort safely, and states after `previousMoved` may transition to `rolledBack` on failure. A promotion is complete only at `remoteVerified`.

## Relationships

- One semantic version configures one Mac bundle and one Android package.
- One validated bundle becomes one DMG.
- One DMG and one APK produce one manifest and two SBOMs.
- One Release set belongs to one channel and one commit.
- One rolling promotion moves one validated rolling Release set to the public rolling tag.
- Update clients later consume the immutable manifest contract but do not depend on signing inputs or promotion state.
