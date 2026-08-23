# Direct distribution packaging application design

## Decisions

1. Publish one immutable `release-manifest.json` with each release artifact set.
2. Use root `VERSION` as authority and require stable tags to match it.
3. Check once asynchronously after app launch and expose manual Settings actions.
4. Keep downloads in temporary app-controlled storage until verified.
5. Open a verified DMG on Mac and hand a verified APK to Android's normal package installer.
6. Use one GitHub Actions workflow and one build-and-validation path for stable and rolling channels.
7. Preserve Git history and all unrelated working-tree changes.

## Architecture summary

The release pipeline produces one cryptographically described artifact set. Both native clients consume the same manifest schema but retain platform-specific download verification and installation handoff. Pure version and metadata logic stays independent from UI. Network and verification logic stays independent from platform installer APIs. UI controllers orchestrate consent and error presentation only.

## Component groups

- **Release contract**: `VERSION`, semantic version rules, `release-manifest.json`, and artifact naming.
- **Release production**: GitHub Actions, package scripts, Mac signing, Android signing, DMG generation, checksums, SBOMs, scans, and validation.
- **Mac update runtime**: BridgeCore manifest/version/network/download components plus a BridgeApp controller using native dialogs and `NSWorkspace`.
- **Android update runtime**: Kotlin manifest/version/network/download components plus PackageManager certificate validation, FileProvider, package-installer intent, and Compose state.
- **Documentation**: Public install guide and maintainer signing/release guide.

## Release manifest contract

Required top-level fields:

- `schemaVersion`
- `version`
- `versionCode`
- `minimumMacOS`
- `minimumAndroidSdk`
- `macos`
- `android`

Each platform artifact contains `name`, `sha256`, and `size`. Android also contains `signerSha256`. Stable names include the semantic version. Rolling names use predictable latest labels. Both clients require the manifest version to match the GitHub Release tag.

## Service orchestration

### Publication

Version validation precedes builds. Signed builds precede DMG/APK validation. Validation precedes manifest generation and full-set verification. SBOM and vulnerability checks precede publication. A failure at any stage prevents release mutation.

### Mac update

A launch or manual request fetches stable metadata and compares strict semantic versions. User consent precedes download. Size and SHA-256 validation precede `NSWorkspace.open`. The app does not overwrite itself.

### Android update

A launch or manual request fetches stable metadata and compares version name and code. User consent precedes download. Size, SHA-256, installed-signer continuity, and manifest fingerprint validation precede FileProvider handoff. Android's installer retains final consent.

## Failure policy

- All malformed or untrusted metadata fails closed.
- Automatic transient network failures do not interrupt normal app use.
- Manual operations display actionable failures.
- Partial, oversized, checksum-failed, and signer-failed downloads are deleted.
- Existing installed apps, settings, user data, privacy grants, and pairing state are never mutated by a failed update check or download.

## Artifact references

- Components: `direct-distribution-packaging-components.md`
- Component methods: `direct-distribution-packaging-component-methods.md`
- Services: `direct-distribution-packaging-services.md`
- Dependencies: `direct-distribution-packaging-component-dependency.md`

## Extension compliance

- **Compliant at design level**: SECURITY-06, SECURITY-09, SECURITY-10, SECURITY-12, SECURITY-13, SECURITY-15.
- **Not applicable**: Remaining security baseline rules because the increment adds no hosted service, database, authentication system, cloud network, or public API.
- **Disabled**: Resiliency baseline and property-based testing for this increment.
- **Blocking next-stage requirement**: Functional and NFR design must convert these boundaries into exact validation rules and tests before implementation.

## Explicit exclusions

No marketplace, Apple notarization, Developer ID purchase, Intel package, Android below 13, silent install, self-replacement, hosted update service, external updater framework, npm package, Homebrew tap, protocol change, branch recreation, history rewrite, or force push.
