# Direct distribution packaging services

## Release publication service

### Inputs

- Root `VERSION`.
- Git event ref and commit SHA.
- Stable macOS signing identity secrets.
- Android keystore bytes, alias, keystore password, and key password secrets.
- Checked-in Swift, Kotlin, Gradle, shell, workflow, and documentation sources.

### Orchestration

1. Checkout with immutable action revisions and minimum permissions.
2. Validate `VERSION`; for stable publication require the tag to match exactly.
3. Import the Mac identity and Android keystore into temporary runner files.
4. Run Swift and Android tests.
5. Build the signed Apple Silicon application and Android release APK.
6. Create and mount-check the DMG.
7. Verify the APK signature and extract its public signer fingerprint.
8. Generate checksums, sizes, manifest, and SBOMs.
9. Run dependency vulnerability checks.
10. Validate the complete local artifact set against the manifest.
11. Publish all assets and release notes as one channel-specific set.
12. Remove temporary signing files through runner teardown and explicit cleanup where supported.

Stable publication uses versioned filenames. Rolling publication updates the `latest-build` prerelease with predictable latest filenames. Both paths execute steps 1 through 10 unchanged.

## Stable release discovery service

### Shared behavior

1. Request GitHub's latest stable Release endpoint for `germanilia/android-bridge`.
2. Require a non-draft, non-prerelease response and strict semantic `vMAJOR.MINOR.PATCH` tag.
3. Locate exactly one `release-manifest.json` asset.
4. Require HTTPS and an approved GitHub host before fetching it.
5. Decode and validate schema, versions, platform constraints, asset metadata, sizes, hashes, and signer fingerprint.
6. Require the manifest version to equal the release tag without its leading `v`.
7. Resolve platform assets only from that same Release response.

The clients never use `latest-build` for update discovery.

## macOS update service

### Automatic check

- `AppDelegate.applicationDidFinishLaunching(_:)` starts normal app services and schedules one detached network operation through `MacUpdateController`.
- Discovery never blocks the main thread or prevents the dashboard from opening.
- No dialog appears when current is equal/newer or when an automatic network check is unavailable.
- A malformed or untrusted response is recorded and exposed on the next manual check; it is never treated as an update.

### Manual check

- Settings invokes the same discovery service with visible progress and success/error output.
- Current version comes from `CFBundleShortVersionString`.

### Confirmed update

1. Present new version and release page link.
2. Download only after user confirmation.
3. Write into a unique temporary directory.
4. Reject excess bytes, size mismatch, checksum mismatch, or file replacement.
5. Open only the verified DMG.
6. Show drag-to-Applications and Control-click then Open guidance.
7. Keep the running and installed app unchanged.

## Android update service

### Automatic and manual checks

- `MainActivity.onCreate` launches one lifecycle-owned check after rendering.
- A Settings tab exposes current version and a manual action.
- Both paths share `AndroidUpdateService`.
- Automatic transient network failure is quiet; manual checks surface actionable errors.
- Invalid trusted metadata always blocks update use.

### Confirmed update

1. Present version and request download consent.
2. Download to a unique subdirectory of `cacheDir`.
3. Enforce manifest byte size and SHA-256.
4. Read the downloaded APK certificate and current installed certificate with `PackageManager`.
5. Require certificate continuity and manifest fingerprint equality.
6. Create a one-time `FileProvider` content URI.
7. Launch Android's normal package installer.
8. Keep mandatory unknown-source and install confirmation visible.
9. Remove partial/rejected files immediately and stale cache files on next app startup.

## Error presentation service rules

- Network unavailable: current app remains usable; manual retry offered.
- No update: manual check reports current version is latest.
- Malformed release or manifest: report invalid release metadata and do not download.
- Size or checksum mismatch: delete file and report integrity failure.
- Android signer mismatch: delete file and report that installation was blocked.
- Installer cancellation: retain installed app and clear stale update files at next launch.
- DMG open failure: retain the verified path for the current interaction and provide safe retry or Finder reveal; never replace the app.

## Security extension compliance

| Rule | Design status | Enforcement |
|---|---|---|
| SECURITY-06 | Compliant | Read-only build jobs; `contents: write` only on publication job or step boundary. |
| SECURITY-09 | Compliant | Supported fixed runner/toolchain and explicit minimum OS versions. |
| SECURITY-10 | Compliant | Immutable action SHAs, lock files, SBOMs, vulnerability scan before publication. |
| SECURITY-12 | Compliant | Secret values only in masked environment variables and temporary signing files. |
| SECURITY-13 | Compliant | SHA-256 for both artifacts plus Android certificate continuity. |
| SECURITY-15 | Compliant | Typed failures, fail-closed validation, cleanup, and unchanged installed apps. |

Other baseline rules remain not applicable because no hosted service, datastore, account, cloud network, or external authentication boundary is introduced.
