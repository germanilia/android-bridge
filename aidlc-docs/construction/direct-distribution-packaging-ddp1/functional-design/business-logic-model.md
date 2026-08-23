# DDP1 business logic model

## Purpose

DDP1 transforms one repository revision plus protected signing inputs into one complete, validated release set. It publishes nothing until every required artifact and gate has succeeded.

## Inputs

| Input | Source | Validation |
|---|---|---|
| Semantic version | Root `VERSION` | Strict `MAJOR.MINOR.PATCH`, no leading zeroes except zero |
| Git ref | GitHub event | `main` push or tag exactly matching `vMAJOR.MINOR.PATCH` |
| Commit SHA | GitHub event | Non-empty full revision used as rolling staging identity |
| Mac signing PKCS#12 | GitHub secret | Present, decodes, imports, exposes expected signing identity |
| Mac signing password | GitHub secret | Present and accepted by import |
| Android keystore | GitHub secret | Present, decodes, and is readable by Gradle signing config |
| Android alias/passwords | GitHub secrets | Present and accepted by signing tools |
| Source tree | Checkout | Tests and production builds pass |

## Version transformation

1. Trim the single trailing newline from `VERSION`.
2. Parse exactly three decimal components.
3. Reject negative values, signs, whitespace inside the value, suffixes, prefixes, empty components, and leading zeroes on multi-digit components.
4. Require minor and patch to be at most 999.
5. Compute Android version code as `major * 1,000,000 + minor * 1,000 + patch`.
6. Require the result to be from 1 through 2,100,000,000.
7. Inject the semantic value into Android `versionName` and macOS `CFBundleShortVersionString`.
8. Inject the numeric value into Android `versionCode` and macOS `CFBundleVersion`.
9. For stable tags, require the event tag to equal `v` followed by the exact semantic value.

Initial source value is `0.1.0`, which derives version code `1000`.

## Channel selection

### Stable

A ref shaped as `refs/tags/vMAJOR.MINOR.PATCH` selects stable only after exact tag-to-file validation.

Stable publication:

- Uses the semantic version in artifact names.
- Creates a non-draft, non-prerelease GitHub Release under the existing tag.
- Refuses to overwrite an existing stable release or stable asset.
- Marks the release as latest only through GitHub's normal stable-release semantics.

### Rolling

A push to `refs/heads/main` selects rolling.

Rolling publication:

- Uses `latest` in public artifact names.
- Builds a complete commit-specific draft prerelease first.
- Keeps the current `latest-build` release untouched until draft upload and remote verification pass.
- Swaps the previous complete release out and the draft into `latest-build` with rollback if promotion fails.
- Deletes the previous release only after the promoted release is verified.

Any other ref is invalid for publication.

## Production flow

1. **Validate source state**: version, event, and required secret presence.
2. **Materialize credentials**: decode into runner-temporary files and isolated temporary keychain.
3. **Build Mac app**: execute the existing Swift release bundler with version and stable identity inputs.
4. **Validate Mac app**: require arm64 executable, expected bundle versions, valid deep signature, and the repository's expected designated requirement.
5. **Build Android app**: execute Gradle `assembleRelease` with temporary signing inputs and derived versions.
6. **Validate Android APK**: require APK signature verification and extract one SHA-256 signer certificate fingerprint.
7. **Create DMG**: stage signed app plus Applications symlink and create a compressed read-only image.
8. **Validate DMG**: attach read-only, require exact root contents, verify copied app architecture, versions, signature, and designated requirement, then detach.
9. **Stage public files**: channel-specific DMG and APK names.
10. **Hash**: calculate byte size and lowercase SHA-256 for each production artifact; create matching checksum files.
11. **Supply-chain evidence**: generate Mac and Android CycloneDX JSON SBOMs and run the pinned vulnerability scanner against locked dependency inputs.
12. **Generate manifest**: encode the validated metadata without credentials or local paths.
13. **Generate notes**: fill version, commit, direct links, supported platforms, update notes, and non-notarized Mac guidance.
14. **Validate release set**: require exact files, manifest/file consistency, checksum consistency, and valid JSON/SBOM documents.
15. **Publish**: use stable create-once or rolling staged promotion.
16. **Verify remote state**: require all expected asset names and manifest metadata on the target Release.

## Artifact set

### Stable `0.1.0` example

- `AndroidBridge-0.1.0-macOS-arm64.dmg`
- `AndroidBridge-0.1.0-macOS-arm64.dmg.sha256`
- `AndroidBridge-0.1.0-macOS-arm64.cdx.json`
- `AndroidBridge-0.1.0-android.apk`
- `AndroidBridge-0.1.0-android.apk.sha256`
- `AndroidBridge-0.1.0-android.cdx.json`
- `release-manifest.json`
- `AndroidBridge-macOS-arm64.dmg` and its checksum as byte-identical direct-download aliases
- `AndroidBridge-android.apk` and its checksum as byte-identical direct-download aliases

The manifest references the versioned canonical DMG and APK. Stable aliases support predictable `/releases/latest/download/` links in README and Setup Wizard.

### Rolling

The canonical list replaces `0.1.0` with `latest`. `release-manifest.json` remains predictable in both channels. Separate stable convenience aliases are unnecessary on rolling because rolling canonical names are already predictable.

## Rolling promotion transaction

1. Create a draft prerelease tagged `latest-build-{commitSHA}` and targeted at the current commit.
2. Upload the complete rolling artifact set.
3. Read back asset names and sizes; fetch and validate the uploaded manifest.
4. If no `latest-build` release exists, rename the draft tag to `latest-build`, then publish it as a prerelease.
5. If a current release exists, remove any stale `latest-build-previous` release/tag, rename the current release tag to `latest-build-previous`, rename the draft tag to `latest-build`, and publish it.
6. Verify the promoted release.
7. Delete `latest-build-previous` only after verification.
8. If promotion fails after moving the current release, move it back to `latest-build` before reporting failure.

The transaction may create a short unavailable interval but must never expose one Release containing artifacts from different commits.

## Failure outcomes

| Failure | Outcome |
|---|---|
| Invalid version/ref/tag | Stop before credential import or build |
| Missing signing input | Stop before packaging |
| Mac identity or requirement mismatch | Stop; publish nothing |
| Android signing or signer extraction failure | Stop; publish nothing |
| Test/build/package failure | Stop; publish nothing |
| DMG/APK/checksum/manifest mismatch | Delete local staged output; publish nothing |
| SBOM/scanner execution failure | Stop; publish nothing |
| High/critical unapproved vulnerability | Stop; publish nothing |
| Stable Release already exists | Stop; never clobber stable release |
| Rolling draft upload failure | Delete draft; preserve current `latest-build` |
| Rolling promotion failure | Execute rollback; preserve or restore prior complete release |
| Remote verification failure | Stable reports failure without mutating an older stable release; rolling restores previous release when possible |

## Documentation flow

- README points normal Mac users to the latest stable Releases page and DMG instructions.
- README identifies Android as optional and links the latest stable APK through the Releases page rather than a version-specific URL.
- Setup wizard uses the stable Releases page or stable release API-derived link, not `latest-build` debug content.
- Maintainer guide lists secret names, key lifecycle, release steps, local non-publishing checks, current Mac self-signing limits, and future Developer ID/notarization path.
