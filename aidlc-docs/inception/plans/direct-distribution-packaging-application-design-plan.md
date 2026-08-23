# Direct distribution packaging application design plan

## Objective

Define the component and service boundaries for the shared release contract, GitHub release packaging, macOS updater, and Android updater before detailed functional and security design.

## Progress

- [x] Analyze approved requirements, workflow plan, current release workflow, macOS package structure, Android Gradle configuration, manifests, and primary UI entry points.
- [x] Resolve application design choices below. User selected all recommended options.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-components.md`.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-component-methods.md`.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-services.md`.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-component-dependency.md`.
- [x] Generate `aidlc-docs/inception/application-design/direct-distribution-packaging-application-design.md`.
- [x] Validate method consistency, dependency direction, platform boundaries, and security-extension compliance.
- [ ] Update this plan immediately as each step completes.

## Design questions

### Q1. Release metadata contract

Which contract should both update clients consume?

- **A. Recommended**: Publish one versioned `release-manifest.json` asset containing schema version, semantic version, Android version code, platform asset names, SHA-256 digests, file sizes, minimum OS versions, and Android signer fingerprint. Clients obtain its URL from the latest stable GitHub Release.
- **B. GitHub fields only**: Infer versions and assets from the GitHub Releases response and parse separate checksum files.
- **C. Static repository file**: Read a manifest from the `main` branch rather than the immutable release.
- **D. Separate platform manifests**: Publish independent Mac and Android metadata files.
- **E. Other**: Describe the exact contract.

[Answer]: A - use one immutable `release-manifest.json` asset.

### Q2. Version source

Where should the release version originate?

- **A. Recommended**: Add root `VERSION` containing `MAJOR.MINOR.PATCH`; derive macOS version, Android `versionName`, and bounded monotonic `versionCode`; require stable tag `vMAJOR.MINOR.PATCH` to match it.
- **B. Tag only**: Stable runs derive from the Git tag while rolling runs use existing project versions.
- **C. Gradle only**: Treat Android Gradle metadata as authoritative and copy it into the Mac build.
- **D. Workflow input**: Enter versions manually when dispatching a release.
- **E. Other**: Describe the authoritative source and rolling behavior.

[Answer]: A - use root `VERSION` and require stable tags to match it.

### Q3. Update discovery timing and UI

How should update checks appear?

- **A. Recommended**: Check once asynchronously after each app launch, show a native confirmation dialog only when newer, and add a manual `Check for Updates` action in Mac Settings and Android Settings.
- **B. Launch only**: Check after every launch with no manual action.
- **C. Manual only**: Never check automatically.
- **D. Daily background cadence**: Persist a last-check timestamp and check at most once per day.
- **E. Other**: Specify trigger, cadence, and UI location.

[Answer]: A - check asynchronously after launch and provide manual Settings actions.

### Q4. Download and install handoff

Which platform handoff should the design use after verification?

- **A. Recommended**: Mac downloads to a temporary update directory, verifies, opens the DMG, and shows drag-to-Applications guidance. Android downloads into app cache, verifies SHA-256 and the archive signer against the installed app signer, then passes a `FileProvider` content URI to Android's package installer.
- **B. User Downloads folder**: Save both files to the visible Downloads directory before verification and handoff.
- **C. Browser handoff**: Open asset URLs in the browser and rely on users to download them.
- **D. Other**: Describe exact storage, verification, and installer handoff.

[Answer]: A - use temporary app-controlled storage and native installer handoff after verification.

### Q5. Workflow organization

How should stable and rolling publication share release logic?

- **A. Recommended**: One pinned GitHub Actions workflow handles `main` pushes and `v*.*.*` tags, runs one build-and-validation path, then selects stable versioned names or rolling latest names during publication.
- **B. Reusable workflow**: Keep separate stable and rolling entry workflows that call a shared reusable workflow.
- **C. Separate workflows**: Duplicate the build steps in independent stable and rolling workflows.
- **D. Other**: Describe the workflow boundary.

[Answer]: A - use one workflow and one shared build-and-validation path.

## Security design constraints

- Update clients trust only HTTPS GitHub API and release URLs owned by `germanilia/android-bridge`.
- A downloaded artifact is never opened or handed to an installer before all required metadata and integrity checks pass.
- Android signer verification uses the installed app certificate as the continuity anchor.
- Android keystore bytes and passwords exist only in secrets and temporary CI files.
- GitHub Actions use minimum permissions and immutable action SHAs.
- Release publication waits for builds, tests, package validation, SBOM generation, and vulnerability checks.
- Failure leaves the installed version untouched and removes untrusted temporary artifacts.

## Scope exclusions

- No marketplace, notarization, Intel build, silent install, app self-replacement, hosted update service, npm packaging, Homebrew tap, or third-party updater framework.
- No Git history rewrite, branch recreation, or force push. Existing repository history and unrelated working-tree changes remain intact.
