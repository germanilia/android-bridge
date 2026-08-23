# DDP3 Android update client code-generation plan

## Approval and adaptive design

Approved for autonomous end-to-end generation by `so make it ready`. DDP3 Functional/NFR decisions are implementation-complete in the approved requirements, Application Design, unit definition, and this plan; no clarification questions or separate NFR stage add value. Existing security controls remain blocking.

## Unit context

- **Requirements**: FR-07; Android runtime portions of FR-04, FR-05, FR-08; NFR-01 through NFR-05; AC-05 through AC-08.
- **Dependency**: DDP1 schema 1, version-code formula, canonical APK/checksum names, and signer fingerprint.
- **Boundary**: pure Kotlin owns version/release/download/hash rules; Android adapter owns PackageManager signer continuity, scoped FileProvider URI, installer intent, lifecycle state, and Compose presentation.
- **Exclusions**: no silent install, Play Store, custom installer, protocol changes, external updater framework, or debug/release signer fallback.

## Exact files

1. `android/app/src/test/kotlin/com/androidbridge/update/AndroidUpdateTest.kt` — new pure Kotlin tests.
2. `android/app/src/main/kotlin/com/androidbridge/update/AndroidUpdate.kt` — new pure Kotlin release/update core.
3. `android/app/src/main/kotlin/com/androidbridge/update/AndroidUpdatePlatform.kt` — new Android verifier/installer/coordinator.
4. `android/app/src/main/kotlin/com/androidbridge/MainActivity.kt` — existing lifecycle and Compose integration.
5. `android/app/src/main/AndroidManifest.xml` — installer permission and scoped provider.
6. `android/app/src/main/res/xml/update_paths.xml` — new cache-only provider path.

## Ordered steps

### Step 1: Tests first

- [x] Add strict semantic/version-code, schema/tag/asset/host, current/newer decision, checksum/size/hash, cleanup, and installer-gating model tests with fakes and temporary directories.

### Step 2: Pure Kotlin update core

- [x] Add strict domain models, typed failures, exact schema decoder, fixed stable GitHub client, redirect-checked bounded downloader, streamed SHA-256, unique cache directories, and `AndroidUpdateService`.
- [x] Require exact canonical APK and checksum from the same stable Release; never use aliases or `latest-build`.

### Step 3: Android trust and installer adapters

- [x] Add `ApkSignatureVerifier` using `PackageManager.GET_SIGNING_CERTIFICATES`; require exactly one installed signer and one archive signer; require archive equals installed and manifest SHA-256.
- [x] Return a typed verified APK accepted by `ApkInstaller` only.
- [x] Add one coordinator exposing finite StateFlow states, automatic/manual checks, consent download, cancellation, stale-cache cleanup, and installer handoff.

### Step 4: Scoped installer declaration

- [x] Add `REQUEST_INSTALL_PACKAGES` and one non-exported grant-URI FileProvider.
- [x] Limit provider XML to updater-owned cache directory.

### Step 5: Existing lifecycle and Compose integration

- [x] Construct one coordinator after normal startup, clean stale files, render UI, then launch one lifecycle-owned automatic check.
- [x] Add Settings tab with installed version, status, manual check, progress, available version, and release link.
- [x] Add native Compose consent and actionable error dialogs. Android system confirmation remains mandatory.

### Step 6: Validation and summary

- [x] Run approved unit tests and debug build.
- [x] Verify release build still fails closed without signing inputs.
- [x] Verify no installer call accepts an unverified APK and no unrelated code was removed.
- [x] Create DDP3 code summary after Sol review.

## Exact checks

1. `cd android && ./gradlew :app:testDebugUnitTest --no-daemon`
2. `cd android && ./gradlew :app:assembleDebug --no-daemon`

## Error and cleanup contract

- External JSON, HTTP, redirects, files, signer metadata, FileProvider, and installer are real boundaries and fail with typed errors.
- Automatic transient network failure is quiet; manual and confirmed-update failures are visible.
- Partial/rejected APKs are deleted immediately. Installer-launched APKs remain only until next startup cleanup.
- Installed app and data are never removed or mutated by updater failure/cancellation.

## Coder restrictions

Terra may edit/write only six exact files and run only two exact checks. No Git, `.git`, branch/worktree, commit/push/release, package publication, signing secret handling, or unrelated refactor.
