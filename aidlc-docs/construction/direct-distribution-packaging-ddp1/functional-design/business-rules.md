# DDP1 business rules

## Version rules

- **DDP1-V01**: `VERSION` contains one strict semantic version without leading `v`.
- **DDP1-V02**: Valid component text is `0` or a non-zero decimal digit followed by decimal digits.
- **DDP1-V03**: Minor and patch are limited to 0 through 999.
- **DDP1-V04**: Android version code is `major * 1,000,000 + minor * 1,000 + patch`.
- **DDP1-V05**: Derived code must be 1 through 2,100,000,000.
- **DDP1-V06**: Stable tag is exactly `v` plus `VERSION`.
- **DDP1-V07**: Mac short version and Android version name equal `VERSION` exactly.
- **DDP1-V08**: Mac bundle version and Android version code equal the derived numeric code.
- **DDP1-V09**: Rolling builds use the repository version; they do not invent timestamp or commit-based app versions.

## Channel rules

- **DDP1-C01**: Only a `main` push or matching semantic tag can publish.
- **DDP1-C02**: Stable releases are neither draft nor prerelease.
- **DDP1-C03**: Rolling releases are prereleases and use public tag `latest-build` after promotion.
- **DDP1-C04**: Stable releases are create-once and never clobbered.
- **DDP1-C05**: Stable and rolling channels run identical build, test, package, scan, manifest, and local validation logic.
- **DDP1-C06**: Channel differences are limited to trigger, public names, release title/notes, prerelease flag, and publication transaction.
- **DDP1-C07**: Runtime update clients consume stable releases only.

## Asset naming rules

Let `{label}` be the semantic version for stable or `latest` for rolling.

- **DDP1-A01**: Mac image is `AndroidBridge-{label}-macOS-arm64.dmg`.
- **DDP1-A02**: Mac checksum is the DMG name plus `.sha256`.
- **DDP1-A03**: Mac SBOM is `AndroidBridge-{label}-macOS-arm64.cdx.json`.
- **DDP1-A04**: Android package is `AndroidBridge-{label}-android.apk`.
- **DDP1-A05**: Android checksum is the APK name plus `.sha256`.
- **DDP1-A06**: Android SBOM is `AndroidBridge-{label}-android.cdx.json`.
- **DDP1-A07**: Manifest is always `release-manifest.json`.
- **DDP1-A08**: A public Release contains exactly one of each required asset name.
- **DDP1-A09**: Checksum files contain lowercase SHA-256, two spaces, the corresponding basename, and one newline.
- **DDP1-A10**: Stable releases additionally contain `AndroidBridge-macOS-arm64.dmg`, `AndroidBridge-macOS-arm64.dmg.sha256`, `AndroidBridge-android.apk`, and `AndroidBridge-android.apk.sha256` as byte-identical convenience aliases for `/releases/latest/download/` links.
- **DDP1-A11**: Stable manifest entries reference versioned canonical artifacts, never convenience aliases.

## Mac package rules

- **DDP1-M01**: DMG root contains `AndroidBridge.app` and an `Applications` symlink only.
- **DDP1-M02**: DMG is compressed and read-only.
- **DDP1-M03**: App executable reports arm64 architecture.
- **DDP1-M04**: App bundle identifier remains `com.androidbridge.mac`.
- **DDP1-M05**: Bundle versions follow DDP1-V07 and DDP1-V08.
- **DDP1-M06**: `codesign --verify --deep --strict` succeeds before and after DMG round-trip.
- **DDP1-M07**: The built and mounted app designated requirements equal the checked-in expected requirement.
- **DDP1-M08**: Missing or changed signing identity never falls back to ad-hoc signing in a public workflow.
- **DDP1-M09**: No installer script, PKG, privileged helper, or automatic Applications replacement is included.

## Android package rules

- **DDP1-D01**: Public Android output is the Gradle release variant.
- **DDP1-D02**: Release build requires temporary keystore path, alias, store password, and key password.
- **DDP1-D03**: No release signing value is committed or printed.
- **DDP1-D04**: APK signature verification succeeds before staging.
- **DDP1-D05**: Exactly one current signer certificate fingerprint is recorded for the first dedicated release key.
- **DDP1-D06**: The manifest fingerprint is uppercase- or lowercase-insensitive input normalized to lowercase hexadecimal without separators.
- **DDP1-D07**: Debug or unsigned fallback is prohibited.
- **DDP1-D08**: `minSdk` remains 33 or newer.

## Manifest rules

- **DDP1-R01**: Schema version is integer `1`.
- **DDP1-R02**: Manifest version and code satisfy all version rules.
- **DDP1-R03**: Minimum macOS is `13.0`; minimum Android SDK is `33`.
- **DDP1-R04**: Each artifact has basename only, byte size greater than zero, and 64-character lowercase SHA-256.
- **DDP1-R05**: Android artifact additionally has a 64-character lowercase signer SHA-256.
- **DDP1-R06**: Manifest names, sizes, and hashes match files in the same local and remote release set.
- **DDP1-R07**: Manifest contains no secret, filesystem path, token, credential, or mutable download URL.
- **DDP1-R08**: Unknown required fields are not introduced without incrementing schema version and updating both clients.

## SBOM and vulnerability rules

- **DDP1-S01**: Each production artifact has one valid CycloneDX JSON SBOM.
- **DDP1-S02**: Scanner and SBOM tool versions are pinned and integrity-verified or invoked through immutable action revisions.
- **DDP1-S03**: Scanner execution failure blocks both channels.
- **DDP1-S04**: High or critical findings block publication.
- **DDP1-S05**: An exception must be checked in before release with identifier, affected component, rationale, owner, expiry, and compensating control; expired exceptions are invalid.
- **DDP1-S06**: No exception may suppress missing signing, checksum, signer, or manifest validation.

## Publication rules

- **DDP1-P01**: Publication begins only after the complete local set validates.
- **DDP1-P02**: Workflow permissions default to read-only; write permission is available only to the publication job.
- **DDP1-P03**: Stable publication fails if the release already exists.
- **DDP1-P04**: Rolling publication uploads to a commit-specific draft before public promotion.
- **DDP1-P05**: Existing `latest-build` remains untouched until draft remote verification succeeds.
- **DDP1-P06**: Failed promotion restores the previous complete rolling release when it was moved.
- **DDP1-P07**: Previous rolling release is deleted only after promoted remote verification succeeds.
- **DDP1-P08**: Remote verification checks release channel, target commit, exact asset names, sizes, and manifest.

## Documentation rules

- **DDP1-U01**: DMG is the primary Mac installation path.
- **DDP1-U02**: Instructions say mount, drag to Applications, and Control-click then Open on first launch.
- **DDP1-U03**: Instructions disclose that the app is not Apple-notarized and never advise disabling Gatekeeper globally.
- **DDP1-U04**: Android is optional and public docs link the stable release-signed APK convenience asset, not a debug APK.
- **DDP1-U05**: Maintainer docs list secret names without values.
- **DDP1-U06**: Android key docs cover creation, offline backup, restore, rotation limits, and permanent upgrade loss if the key changes.
- **DDP1-U07**: Mac docs cover current self-signed identity continuity and future Developer ID/notarization migration.
- **DDP1-U08**: Local validation commands do not publish or print credentials.

## Error rules

- **DDP1-E01**: Every failed gate exits non-zero with the failed rule and safe next action.
- **DDP1-E02**: Secret values and decoded key bytes never appear in diagnostics.
- **DDP1-E03**: Missing required inputs fail before publication mutation.
- **DDP1-E04**: Local partial artifacts remain outside Git and are safe to delete.
- **DDP1-E05**: Rolling failure must not leave one public Release containing mixed-commit assets.
- **DDP1-E06**: Cleanup failure is reported; it never changes a validation failure into success.

## Security extension compliance

- SECURITY-06: DDP1-P02.
- SECURITY-09: pinned supported build environments and minimum platforms in DDP1-R03/S02.
- SECURITY-10: DDP1-S01 through DDP1-S05.
- SECURITY-12: DDP1-D02/D03 and DDP1-E02.
- SECURITY-13: DDP1-A09, DDP1-M06/M07, DDP1-D04 through DDP1-D06, and DDP1-R04 through DDP1-R06.
- SECURITY-15: DDP1-P01 through DDP1-P08 and DDP1-E01 through DDP1-E06.

No applicable rule is deferred without an owning business rule. Remaining baseline rules are not applicable to this unit.
