# Direct distribution packaging units of work

## Decomposition model

This brownfield increment remains one monorepo and two native applications. Units are logical development modules, not independently deployed services. Unit 1 owns and freezes the language-neutral release contract before Units 2 and 3 consume it.

## DDP1: Release packaging and signing

### Purpose

Produce complete, validated stable and rolling release artifact sets for Apple Silicon Macs and Android 13+ phones.

### Responsibilities

- Add root semantic version authority and deterministic Android version-code derivation.
- Define and generate `release-manifest.json`.
- Inject the version into the macOS bundle and Android app.
- Configure Android release signing from CI-only environment inputs and fail when missing.
- Build, sign, package, and validate the Apple Silicon app in a DMG.
- Build and verify a release-signed APK.
- Produce SHA-256 checksum files, SBOMs, vulnerability scan results, and release notes.
- Publish versioned stable releases from matching tags and atomic rolling `latest-build` releases from `main`.
- Make DMG installation primary in README and setup guidance.
- Document signing secrets, Android key continuity, local validation, stable release procedure, and future notarization.

### Owned requirements

- FR-01 through FR-05.
- FR-08 and FR-09.
- Release-production portions of NFR-01 through NFR-05.
- Acceptance criteria 1 through 5 and 9.

### Inputs

- Existing native Mac and Android sources.
- Existing stable self-signed Mac identity mechanism.
- GitHub Actions secrets for Mac and Android signing.
- Git event ref and commit SHA.

### Outputs

- Frozen version, manifest, and asset naming contract.
- Validated DMG, APK, checksum, SBOM, manifest, and notes assets.
- One stable/rolling release workflow.
- Public and maintainer documentation.

### Construction stages

- Functional Design: exact version, naming, manifest, packaging, and publication rules.
- NFR Requirements: signing, permissions, reproducibility, compatibility, and failure requirements.
- NFR Design: secret lifetime, integrity checks, scanning, SBOM, atomic publication, and validation mapping.
- Infrastructure Design: skipped; GitHub Actions is existing release tooling, not new hosted infrastructure.
- Code Generation: scripts, workflow, version integration, tests, and docs.

### Done conditions

- Local non-publishing package validation succeeds.
- Workflow syntax and event/channel logic are verified.
- Stable publication remains blocked when signing inputs, version/tag consistency, scans, or artifact validation fail.
- Contract is ready for both runtime update clients.

## DDP2: macOS update client

### Purpose

Let the native macOS app discover a stable release, obtain user consent, verify its DMG, and open it without replacing the running app.

### Responsibilities

- Implement strict semantic version and manifest decoding in BridgeCore.
- Fetch only the latest stable release for `germanilia/android-bridge` over HTTPS.
- Validate repository, release channel, tag, manifest schema, platform constraints, and asset metadata.
- Compare against `CFBundleShortVersionString` asynchronously.
- Add one launch check and one manual Settings action.
- Present native consent, progress, no-update status, and actionable errors.
- Download into a unique temporary directory only after consent.
- Enforce size and SHA-256 before opening the DMG.
- Open the verified DMG and show drag-to-Applications plus Control-click then Open guidance.
- Clean partial and rejected files without mutating the installed app.

### Owned requirements

- FR-06.
- Mac runtime portions of FR-03, FR-05, and FR-08.
- Runtime portions of NFR-01 through NFR-05 for macOS.
- Acceptance criteria 6 through 8 for macOS.

### Inputs

- Frozen DDP1 manifest and asset contract.
- Installed bundle version.
- GitHub latest stable Release response.
- Explicit user download consent.

### Outputs

- BridgeCore release/update domain types and services.
- BridgeApp update controller, dialogs, and Settings action.
- Example-based Swift tests for version, metadata, selection, integrity, and cleanup.

### Construction stages

- Functional Design: state transitions, parsing, comparison, discovery, consent, download, validation, and cleanup.
- NFR Requirements: HTTPS trust, startup isolation, memory/disk bounds, compatibility, and usability.
- NFR Design: dependency injection, fail-closed checks, temporary storage, and UI error mapping.
- Infrastructure Design: skipped.
- Code Generation: Swift core, UI integration, and tests.

### Done conditions

- Launch is never blocked by update discovery.
- Newer stable versions prompt before download.
- Modified or malformed artifacts never open.
- Equal/newer installed versions produce no automatic prompt.
- Existing application and user data remain unchanged on every failure.

## DDP3: Android update client

### Purpose

Let the Android app discover a stable release, obtain user consent, verify the release APK and signer, and invoke Android's normal installer.

### Responsibilities

- Implement strict semantic version and manifest decoding in Kotlin.
- Fetch and validate only the latest stable release and Android asset.
- Compare manifest version and code with `BuildConfig` values.
- Add one lifecycle-owned launch check and a Settings tab/manual action.
- Present consent, progress, no-update status, cancellation, and actionable errors.
- Download into app cache only after consent.
- Enforce size and SHA-256.
- Compare archive signer certificate with the installed app signer and manifest fingerprint.
- Add scoped FileProvider configuration and package-installer handoff.
- Preserve Android's unknown-source and installation confirmation screens.
- Remove partial, rejected, and stale update files.

### Owned requirements

- FR-07.
- Android runtime portions of FR-04, FR-05, and FR-08.
- Runtime portions of NFR-01 through NFR-05 for Android.
- Acceptance criteria 5 through 8 for Android.

### Inputs

- Frozen DDP1 manifest and asset contract.
- Installed app version and signing certificate.
- GitHub latest stable Release response.
- Explicit user download consent.

### Outputs

- Kotlin release/update domain types and services.
- Android signer verifier and installer adapter.
- Compose update states, dialogs, and Settings tab.
- FileProvider manifest/resource configuration.
- Example-based Kotlin tests and physical-device validation instructions.

### Construction stages

- Functional Design: state transitions, metadata validation, version checks, consent, download, signer continuity, installer handoff, and cleanup.
- NFR Requirements: HTTPS trust, startup isolation, storage bounds, Android compatibility, and consent usability.
- NFR Design: injectable clients, fail-closed integrity chain, PackageManager checks, scoped URI, and error mapping.
- Infrastructure Design: skipped.
- Code Generation: Kotlin core/platform/UI, resources, manifest, and tests.

### Done conditions

- App startup is not blocked by discovery.
- Download requires consent and installation requires Android system confirmation.
- Wrong checksum or signer blocks installer invocation and deletes the APK.
- A same-key later release can upgrade the installed release build.
- Existing app and data survive failure or cancellation.

## Integrated completion

After DDP1, DDP2, and DDP3 complete:

1. Build one local release artifact set from the frozen contract.
2. Run all Swift, Kotlin, package, workflow, integrity, and documentation checks.
3. Prove both clients accept valid metadata and reject tampered metadata/artifacts.
4. Confirm configured GitHub signing secrets without printing values.
5. Commit and push only after full-diff review.
6. Publish stable and rolling packages only after CI succeeds and the existing history is preserved.
