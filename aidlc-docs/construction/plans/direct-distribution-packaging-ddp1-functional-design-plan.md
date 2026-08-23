# DDP1 release packaging and signing functional-design plan

## Objective

Define exact business rules, domain entities, transformations, validation order, channel behavior, artifact naming, and failure outcomes for release packaging before security NFR design and code generation.

## Progress

- [x] Analyze DDP1 responsibilities, requirement allocation, dependencies, and current rolling workflow.
- [x] Confirm DDP1 contains release production and documentation, not runtime update UI.
- [x] Resolve functional-design questions below. User selected every recommended option and requested recommended defaults thereafter.
- [x] Generate `aidlc-docs/construction/direct-distribution-packaging-ddp1/functional-design/business-logic-model.md`.
- [x] Generate `aidlc-docs/construction/direct-distribution-packaging-ddp1/functional-design/business-rules.md`.
- [x] Generate `aidlc-docs/construction/direct-distribution-packaging-ddp1/functional-design/domain-entities.md`.
- [x] Validate DDP1 logic against FR-01 through FR-05, FR-08, FR-09, and acceptance criteria 1 through 5 and 9.
- [x] Record security-extension applicability without designing infrastructure controls prematurely.
- [x] Update this plan as each step completes.

## Category assessment

- **Business logic modeling**: Applicable to version derivation, build channels, artifact transformation, validation, and publication.
- **Domain model**: Applicable to semantic versions, channels, artifact descriptors, signing identity metadata, manifests, and release sets.
- **Business rules**: Applicable to naming, tag consistency, signer continuity, required assets, and publication gates.
- **Data flow**: Applicable from source/version/secrets through signed artifacts and public Release assets. No application datastore is introduced.
- **Integration points**: GitHub Actions, GitHub Releases, macOS `codesign`/`hdiutil`, Gradle, Android signing tools, SBOM tooling, and vulnerability scanning.
- **Error handling**: Fail-closed behavior is required for version, signing, package, scan, and publication failures.
- **Business scenarios**: Stable release, rolling release, first release, missing secrets, changed signer, partial publication, and rollback.
- **Frontend components**: Not applicable. DDP1 changes documentation and setup links but introduces no runtime UI component.

## Functional-design questions

### Q1. Initial version and version-code mapping

What initial authoritative version and numeric mapping should DDP1 use?

- **A. Recommended**: Start root `VERSION` at existing `0.1.0`; derive Android `versionCode` as `major * 1_000_000 + minor * 1_000 + patch`; require minor and patch from 0 through 999 and total code from 1 through 2,100,000,000.
- **B. Start at 1.0.0**: Publish the first stable direct-distribution release as `v1.0.0`.
- **C. Incremental integer file**: Maintain a separate manually edited Android version-code file.
- **D. Timestamp code**: Derive Android version code from build time.
- **E. Other**: Give the version and exact monotonic mapping.

[Answer]: A - start at `0.1.0` and use the bounded base-1000 version-code mapping.

### Q2. Stable and rolling asset names

Which naming policy should be frozen?

- **A. Recommended**: Stable names use `AndroidBridge-{version}-macOS-arm64.dmg`, `AndroidBridge-{version}-android.apk`, matching `.sha256` files, platform CycloneDX JSON SBOMs, and `release-manifest.json`; rolling names replace `{version}` with `latest` while retaining platform and architecture.
- **B. Tag in names**: Include the leading `v` in stable filenames.
- **C. Minimal names**: Use `AndroidBridge.dmg` and `AndroidBridge.apk` for every channel.
- **D. Keep Mac ZIP**: Publish ZIP and DMG as equal primary artifacts.
- **E. Other**: Provide every required filename.

[Answer]: A - use explicit stable versions and predictable `latest` platform names.

### Q3. DMG layout

What should users see after mounting the DMG?

- **A. Recommended**: A signed `AndroidBridge.app` plus an `Applications` symlink in a read-only compressed DMG; no custom installer or background script.
- **B. App only**: Include only `AndroidBridge.app` with written copy instructions.
- **C. PKG inside DMG**: Add a package installer.
- **D. Script inside DMG**: Include an installation shell script.
- **E. Other**: Describe exact mounted contents and interaction.

[Answer]: A - ship the app and Applications symlink in a read-only compressed DMG.

### Q4. Rolling publication replacement

How should the workflow avoid leaving a partial mixed rolling release?

- **A. Recommended**: Build and validate everything first, create a commit-specific draft prerelease with all predictable `latest` assets, then swap its release tag to `latest-build`; retain or restore the previous complete release if the swap fails.
- **B. In-place clobber**: Upload each asset directly to the existing `latest-build` release.
- **C. Immutable rolling tags only**: Publish `build-{sha}` releases and remove the predictable `latest-build` URL.
- **D. No rolling APK**: Keep only the Mac rolling artifact.
- **E. Other**: Define an atomic or recoverable publication transaction.

[Answer]: A - stage a complete commit-specific draft before swapping `latest-build`, with rollback.

### Q5. Missing or changed signing inputs

What should happen when signing configuration is unavailable or inconsistent?

- **A. Recommended**: Fail before packaging or publication; keep the previous rolling release unchanged; require the Mac designated requirement expected by the repository and require the Android signer fingerprint generated from the configured long-lived key.
- **B. Debug fallback**: Publish a debug APK when Android release secrets are missing.
- **C. Ad-hoc Mac fallback**: Publish an ad-hoc Mac build when the stable identity is missing.
- **D. Publish unsigned artifacts**: Warn but continue.
- **E. Other**: Define channel-specific fallback rules.

[Answer]: A - fail closed on missing or inconsistent stable signing inputs.

### Q6. SBOM and vulnerability policy

Which release-gate policy should Functional Design carry into NFR Design?

- **A. Recommended**: Generate one CycloneDX JSON SBOM for each production artifact using a pinned scanner; scan locked Swift and Gradle dependencies with a pinned vulnerability scanner; block stable and rolling publication on scanner execution failure or findings rated high/critical, and document any explicit time-bounded exception before release.
- **B. Stable only**: Run SBOM and vulnerability gates only for semantic tags.
- **C. Report only**: Publish even when high/critical findings exist.
- **D. GitHub alerts only**: Do not run release-time scanning.
- **E. Other**: Define formats, scope, thresholds, and exception policy.

[Answer]: A - generate CycloneDX SBOMs and block on scanner failure or high/critical findings.

### Q7. Release notes and documentation source

How should release notes be produced?

- **A. Recommended**: Keep a checked-in release-notes template and maintainer guide; workflow fills version, commit, direct asset links, supported platforms, update guidance, and non-notarized Mac limitation; README links the stable Releases page rather than hardcoding a version.
- **B. GitHub auto-notes only**: Use generated commit notes without installation sections.
- **C. Manual notes**: Require maintainers to type all notes in the GitHub UI.
- **D. README only**: Publish no release-specific notes.
- **E. Other**: Describe the source and required sections.

[Answer]: A - use a checked-in template and guide, with workflow-filled release details.

## Proposed validation order

1. Parse root version and derive Android version code.
2. Validate event channel and stable tag consistency.
3. Confirm all required secret inputs exist without printing values.
4. Import temporary signing material.
5. Run source tests and production builds.
6. Validate Mac architecture/designated requirement and Android signer.
7. Build and mount-check DMG; stage release APK.
8. Calculate sizes and SHA-256 digests.
9. Generate SBOMs and run vulnerability gates.
10. Generate release manifest and notes.
11. Validate the complete local release set.
12. Publish through stable or recoverable rolling transaction.
13. Verify published asset names and manifest consistency.

## Explicit exclusions

No runtime updater code, marketplace, notarization, Developer ID purchase, Intel artifact, debug APK fallback, silent installer, protocol change, branch creation, history rewrite, or force push.
