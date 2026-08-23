# DDP3 Android update client code-generation summary

## Result

The Android app now discovers only the fixed latest stable GitHub Release, validates the DDP1 contract, asks before downloading, verifies checksum, size, SHA-256, and signer continuity, and hands only a verified APK to Android's normal package installer.

## Created

- `android/app/src/main/kotlin/com/androidbridge/update/AndroidUpdate.kt`
- `android/app/src/main/kotlin/com/androidbridge/update/AndroidUpdatePlatform.kt`
- `android/app/src/test/kotlin/com/androidbridge/update/AndroidUpdateTest.kt`
- `android/app/src/main/res/xml/update_paths.xml`

## Modified

- `android/app/src/main/kotlin/com/androidbridge/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`

## Trust controls

- Fixed repository and latest-stable endpoint.
- Strict semantic version and derived version-code agreement.
- Exact schema, stable tag, canonical same-Release APK/checksum, platform values, sizes, hashes, and signer fingerprint.
- Redirect-inspected bounded HTTPS retrieval.
- Consent before checksum/APK retrieval.
- Installed signer, archive signer, and manifest signer must all match.
- `ApkInstaller` accepts only `VerifiedApk` and uses a cache-only non-exported FileProvider.
- Android's unknown-source and installation confirmation remains visible.
- Partial, rejected, cancelled, and stale update files receive scoped cleanup.

## Validation

- Terra initial tests and debug build passed.
- One focused Terra repair hardened malformed external input, cancellation, cleanup, returned filenames, PackageManager/FileProvider errors, and lifecycle cancellation.
- A stale Gradle incremental source snapshot initially omitted two preserved untracked Kotlin files; `--rerun-tasks` refreshed the source set and normal checks then passed.
- Sol independently ran Android unit tests and debug assembly successfully.
- A local release APK built with the new long-lived release keystore and passed apksigner verification using v2 signing.
- Release signer SHA-256: `108b8f8ac860041b0845c9c426cfe7125c8e99899cde031791359a180f233410`.

## Remaining runtime evidence

A physical same-key upgrade requires two published release versions. The currently connected developer installation is debug-signed and intentionally cannot impersonate the public release signer.
