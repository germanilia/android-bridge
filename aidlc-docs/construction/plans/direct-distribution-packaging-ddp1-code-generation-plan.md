# DDP1 release packaging and signing code-generation plan

This document is the single source of truth for DDP1 Code Generation and the implementation-grade Pi Develop brief for Terra.

## Planning progress

- [x] Read DDP1 unit, dependency, requirement map, Functional Design, current workflow, Mac bundler, Android Gradle configuration, README, setup link, installer, lock files, and working-tree diff.
- [x] Confirm DDP1 dependencies are satisfied and its release contract can be implemented before DDP2/DDP3.
- [x] Identify exact brownfield files to modify and new files to create.
- [x] Define exact implementation order, approved files, approved checks, and security gates.
- [x] Validate approved checks contain no Git, Pi, Claude, destructive filesystem, or `.git` operations.
- [x] Obtain explicit approval of this complete code-generation plan.

## Goal

Implement DDP1 so one root version drives production Mac and Android metadata; local tooling creates and validates a signed Apple Silicon DMG, release APK metadata, checksums, CycloneDX SBOM references, manifest, and notes; GitHub Actions builds the same complete stable or rolling release set with protected signing inputs; public docs make stable DMG/APK installation direct and safe.

## Acceptance criteria

- Root `VERSION` is `0.1.0`; strict parsing derives Android/macOS build number `1000`.
- Android debug work remains usable without release secrets; every requested release task fails clearly unless all four Android signing environment variables exist.
- `mac/scripts/make-macos-app.sh` writes root version/build metadata while preserving all current Calendar permission and designated-requirement continuity logic.
- A checked-in distribution requirement binds public Mac packages to certificate SHA-1 `EF2FB966BB80189B6E12EF4A9111601F4D8466EC` and bundle identifier `com.androidbridge.mac`.
- `scripts/make-dmg.sh` produces a read-only compressed DMG containing only signed `AndroidBridge.app` and an `/Applications` symlink and verifies the mounted copy.
- `scripts/release.py` generates and validates canonical artifact names, checksums, manifest schema 1, notes, sizes, hashes, and Android signer fingerprint shape without handling secret values.
- Stable Releases contain versioned canonical artifacts plus byte-identical predictable DMG/APK aliases and alias checksums. Rolling uses predictable `latest` canonical names.
- Build job has `contents: read`; publication job alone has `contents: write`.
- All actions use immutable SHAs. Syft is pinned to `1.51.0`; Grype is pinned to `0.117.0` with high severity cutoff and build failure enabled.
- Stable publication is create-once. Rolling publication stages and remotely verifies a complete commit-specific draft before replacing `latest-build`, with rollback logic.
- README and Setup Wizard link normal users to stable direct assets. The shell installer remains advanced and consumes the rolling DMG with checksum verification.
- Maintainer documentation lists secret names only and covers Android key backup/continuity, Mac identity, stable tags, rolling behavior, local checks, and future notarization.
- No secret, key, password, token, decoded credential, or generated production artifact enters Git.

## Repository evidence

### Exact files read

- `.github/workflows/release-macos.yml`
- `.gitignore`
- `README.md`
- `install.sh`
- `android/app/build.gradle.kts`
- `android/build.gradle.kts`
- `android/settings.gradle.kts`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `mac/Package.swift`
- `mac/Package.resolved`
- `mac/scripts/make-macos-app.sh`
- `mac/Sources/BridgeApp/SetupWizardView.swift`
- DDP1 unit, dependency, requirement map, and all Functional Design artifacts

### Existing verified symbols and behavior

- Android module begins `plugins { id("com.android.application") ... }` and owns `android { defaultConfig { ... versionCode = 1; versionName = "0.1.0" } }` plus `buildTypes { getByName("release") { isMinifyEnabled = false } }`.
- Existing Mac entry script is `mac/scripts/make-macos-app.sh`; it sets `APP="$MAC_DIR/dist/AndroidBridge.app"`, writes `CFBundleShortVersionString` and `CFBundleVersion`, requires `CODESIGN_IDENTITY`, verifies with `codesign`, and preserves the installed designated requirement.
- Existing public workflow is `.github/workflows/release-macos.yml`, runs only on `main`, builds Android with `./gradlew :app:assembleDebug --no-daemon`, packages a Mac ZIP, and clobbers assets in `latest-build`.
- Existing workflow checkout is pinned to `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`.
- Existing setup link is `private var apkURL: URL { URL(string: "https://github.com/germanilia/android-bridge/releases/download/latest-build/AndroidBridge-latest.apk")! }`.
- Existing installer constants are `RELEASE_TAG="latest-build"`, `ARCHIVE_NAME="AndroidBridge-macOS-arm64.zip"`, and checksum derived from that archive.
- Current local public-style identity is `Android Bridge Distribution`, SHA-1 `EF2FB966BB80189B6E12EF4A9111601F4D8466EC`.
- Current installed local identity requirement is different (`A0B15...`), so implementation must preserve local install continuity and enforce the distribution requirement only when the public packaging path requests it.
- Current `mac/scripts/make-macos-app.sh` has pre-existing uncommitted Calendar permission and safe staged-install changes. They must remain intact.
- Gradle wrapper is `8.10.2`; Android plugins are fixed at AGP `8.6.1` and Kotlin `2.0.21`; Swift dependencies are revision-locked in `mac/Package.resolved`.

## Files and ordered edits

### Step 1 - Root version contract

- [x] Create `VERSION` containing exactly `0.1.0` plus newline.

Current behavior: Mac and Android hardcode separate version values.

Required change: establish one source consumed by Python, Gradle, and Mac bundling.

Edge cases: missing file, extra lines, whitespace, malformed components, component bounds, and derived Android maximum fail explicitly.

### Step 2 - Release domain tooling and unit tests

- [x] Create `scripts/release.py` using Python standard library only.
- [x] Create `scripts/test_release.py` with `unittest` cases.

Required exact public symbols:

- `VERSION_PATTERN`
- `@dataclass(frozen=True) class SemanticVersion`
- `def parse_version(value: str) -> SemanticVersion`
- `def read_version(path: Path) -> SemanticVersion`
- `def artifact_names(version: SemanticVersion, channel: str) -> dict[str, str]`
- `def sha256_file(path: Path) -> str`
- `def build_manifest(version: SemanticVersion, names: dict[str, str], directory: Path, signer_sha256: str) -> dict[str, object]`
- `def validate_manifest(manifest: dict[str, object], directory: Path) -> None`
- `def write_checksum(path: Path) -> Path`
- `def render_notes(template: Path, output: Path, version: SemanticVersion, commit: str, repository: str, channel: str, names: dict[str, str]) -> None`
- `def main() -> int`

CLI subcommands:

- `version --root PATH [--check-tag TAG] [--field version|code]`
- `manifest --root PATH --channel stable|rolling --directory PATH --android-signer SHA256 --output PATH`
- `validate --root PATH --channel stable|rolling --directory PATH --manifest PATH`
- `notes --root PATH --channel stable|rolling --commit SHA --repository OWNER/REPO --template PATH --output PATH`

Implementation rules:

- Version parser uses strict decimal syntax and the approved base-1000 mapping.
- `artifact_names` returns canonical names, checksum names, and SBOM names. For stable it also returns predictable direct alias names/checksums.
- Manifest has exactly schema/version/versionCode/minimumMacOS/minimumAndroidSdk/macos/android fields. Platform entries contain canonical name/size/sha256; Android adds signerSha256.
- Stable aliases must be byte-identical to canonical files; manifest never references them.
- SHA/signers normalize only from strict 64-digit hexadecimal input; malformed values fail.
- Notes renderer replaces a fixed token set and fails if an unknown or unreplaced token remains.
- Errors reach CLI as concise stderr and exit code 1; no broad exception swallowing.

Tests:

- `0.1.0 -> 1000`, numeric ordering inputs, maximum boundaries, and representative invalid values.
- Stable and rolling canonical names plus stable aliases.
- Manifest success with temporary files.
- Wrong size/hash/name/signer/schema/version and non-identical alias rejection.
- Checksum exact format.
- Notes token replacement and unreplaced-token failure.
- Repository policy assertions: immutable action references, release APK task, no debug public build, least-privilege job permissions, direct stable links, and required secret names.

### Step 3 - Android version and release signing

- [x] Modify `android/app/build.gradle.kts` in place.

Current behavior: `versionCode = 1`, `versionName = "0.1.0"`, and release has no signing config.

Required change:

- Read `../VERSION`, validate strict semantic syntax, derive bounded numeric code, and assign both values in `defaultConfig`.
- Read environment providers named exactly:
  - `ANDROID_RELEASE_STORE_FILE`
  - `ANDROID_RELEASE_STORE_PASSWORD`
  - `ANDROID_RELEASE_KEY_ALIAS`
  - `ANDROID_RELEASE_KEY_PASSWORD`
- Detect whether requested Gradle task names contain `release`, case-insensitively.
- For release requests, list missing variable names and throw one `GradleException` before task execution without values.
- Create `signingConfigs.create("release")` only when all values exist, then bind `buildTypes.release.signingConfig`.
- Preserve compile SDK, minimum SDK 33, target SDK, dependencies, test configuration, and existing release minification choice.

No keystore path, alias, or password default is allowed.

### Step 4 - Mac version and distribution identity

- [x] Modify `mac/scripts/make-macos-app.sh` in place while preserving all pre-existing uncommitted changes.
- [x] Create `mac/distribution-signing-requirement.txt` containing exactly `identifier "com.androidbridge.mac" and certificate leaf = H"ef2fb966bb80189b6e12ef4a9111601f4d8466ec"` plus newline.

Required change in `make-macos-app.sh`:

- Define repository root from `MAC_DIR`.
- Ask `scripts/release.py version` for semantic version and numeric code.
- Insert those values into `CFBundleShortVersionString` and `CFBundleVersion`.
- If `EXPECTED_CODESIGN_REQUIREMENT_FILE` is set, require the file and compare its exact line with the built requirement after signing.
- Keep current default local identity `A0B15...`, explicit `CODESIGN_IDENTITY` override, Calendar privacy strings, codesign verification, safe installed-app staging, installed requirement comparison, and `NO_INSTALL` behavior.
- Never silently fall back to another identity.

### Step 5 - DMG production and verification

- [x] Create executable `scripts/make-dmg.sh`.

CLI: `scripts/make-dmg.sh APP_PATH OUTPUT_DMG EXPECTED_REQUIREMENT_FILE`.

Control flow:

1. Fail unless running on Darwin arm64 and all three arguments exist.
2. Read expected version/code through `scripts/release.py`.
3. Verify app directory, executable, bundle identifier, versions, arm64 architecture, deep strict code signature, and exact designated requirement.
4. Stage app with `ditto`, create `Applications -> /Applications`, and build UDZO read-only DMG with `hdiutil create`.
5. Attach with `hdiutil attach -readonly -nobrowse -plist`, extract mount point with `/usr/libexec/PlistBuddy`, and register cleanup trap.
6. Require root entries are exactly `AndroidBridge.app` and `Applications`; require symlink target `/Applications`.
7. Repeat app metadata, architecture, signature, and requirement validation on mounted copy.
8. Detach and report output path. Cleanup failure must fail the command.

No installer, PKG, hidden executable, or app replacement.

### Step 6 - Release templates and maintainer documentation

- [x] Create `.github/release-notes-template.md` with only supported renderer tokens.
- [x] Create `docs/RELEASING.md`.

Template required sections:

- Version and source commit.
- Direct stable or rolling DMG/APK links.
- Apple Silicon macOS 13+ installation.
- Optional Android 13+ installation.
- Update notes.
- Explicit non-notarized Mac warning and Control-click then Open guidance.
- Checksums/SBOM reference.

Maintainer guide required secret names:

- `MACOS_SIGNING_P12`
- `MACOS_SIGNING_PASSWORD`
- `ANDROID_RELEASE_KEYSTORE_B64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

Guide must include keytool creation without example real passwords, offline encrypted backup, restore test, lost-key consequences, no practical in-place rotation for current sideloaded installs, Mac P12 identity continuity, local non-publishing checks, matching `VERSION` plus `vMAJOR.MINOR.PATCH` stable tag procedure, rolling behavior, stable alias behavior, and future Developer ID/notarization path.

### Step 7 - Public installation surfaces and advanced installer

- [x] Modify `README.md` in place.
- [x] Modify `mac/Sources/BridgeApp/SetupWizardView.swift` in place at `androidPhone` and `apkURL`.
- [x] Modify `install.sh` in place.

README:

- Replace one-line CLI installation as primary with stable DMG direct link `https://github.com/germanilia/android-bridge/releases/latest/download/AndroidBridge-macOS-arm64.dmg`.
- Explain mount, drag to Applications, and Control-click then Open.
- State no Apple notarization because there is no paid Developer account; never recommend disabling Gatekeeper.
- Add optional stable APK direct link `https://github.com/germanilia/android-bridge/releases/latest/download/AndroidBridge-android.apk` and Android's unknown-source/system consent.
- Keep `install.sh` in an Advanced command-line installation subsection and describe it as rolling.
- Update source-build/release-signing wording and link `docs/RELEASING.md`.

Setup Wizard:

- Change `apkURL` to the stable direct APK alias.
- Remove `debug-signed` wording and identify it as optional, release-signed, Android 13+.
- Preserve QR and current layout.

Installer:

- Replace ZIP constants with rolling `AndroidBridge-latest-macOS-arm64.dmg` and checksum.
- Download over enforced HTTPS and verify checksum.
- Attach DMG read-only/no-browse, require `AndroidBridge.app`, stage it, verify deep code signature, then replace `/Applications/AndroidBridge.app` only because the user explicitly invoked the advanced installer.
- Always detach and delete temporary data with a trap.
- Preserve Apple Silicon/macOS checks and clear errors.

### Step 8 - Shared stable/rolling GitHub Actions pipeline

- [x] Replace `.github/workflows/release-macos.yml` in place; do not create a duplicate workflow.

Triggers:

- Push to `main`.
- Push tags matching `v*.*.*`; `scripts/release.py` rejects malformed or mismatched tags.

Permissions and concurrency:

- Top-level `contents: read`.
- `build-and-validate` job: `contents: read`, `macos-15`, concurrency keyed by ref without cancelling stable tags.
- `publish` job: needs build, `contents: write` only.

Immutable actions:

- `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`
- `actions/setup-java@c5195efecf7bdfc987ee8bae7a71cb8b11521c00`, Temurin JDK 17, Gradle cache.
- `anchore/sbom-action@e22c389904149dbc22b58101806040fa8d37a610`, `syft-version: 1.51.0`, `format: cyclonedx-json`, action artifact/release upload disabled.
- `anchore/scan-action@e1165082ffb1fe366ebaf02d8526e7c4989ea9d2`, `grype-version: 0.117.0`, scan each SBOM, `severity-cutoff: high`, `fail-build: true`.
- `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` with missing-file error and short retention.
- `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093`.

Build job order:

1. Checkout and set stable/rolling channel/label through `scripts/release.py`.
2. Validate all six signing secrets are non-empty by variable name only.
3. Decode P12 and Android keystore into `$RUNNER_TEMP`; import isolated Mac keychain; never echo values.
4. Run Python release tests, `swift test`, and Android debug unit tests.
5. Build Mac app with `NO_INSTALL=1`, `CODESIGN_IDENTITY="Android Bridge Distribution"`, and distribution requirement file.
6. Build `:app:assembleRelease` with exact Android environment variables.
7. Verify APK with build-tools 34 `apksigner`, require one signer, and extract normalized SHA-256.
8. Create channel-named DMG and stage channel-named APK in `release-dist`.
9. For stable, copy byte-identical predictable aliases.
10. Write checksum files through `scripts/release.py`.
11. Generate Mac and Android CycloneDX JSON SBOMs and scan both at high threshold.
12. Generate manifest and notes; validate complete local set.
13. Upload one workflow artifact containing only public release files and notes.
14. Always remove temporary keychain and credential files without masking prior failure.

Publish job:

- Download and validate the artifact again.
- Stable: fail if release already exists; create against exact tag with notes and all public assets; verify remote exact names and sizes.
- Rolling: create commit-specific draft prerelease, upload all files, verify; preserve current complete release until staging verifies; promote staging to `latest-build`; on any promotion failure restore prior release/tag; delete prior only after final remote verification.
- Never publish notes file itself as a release asset.

### Step 9 - Validation and traceability

- [x] Run all approved checks below.
- [x] Verify no duplicate brownfield files were created.
- [x] Verify no key/secret material or generated release output is tracked.
- [x] Verify FR-01 through FR-05, FR-08, FR-09 and DDP1 security rules map to code/tests/docs.

### Step 10 - DDP1 code summary

- [x] Sol creates `aidlc-docs/construction/direct-distribution-packaging-ddp1/code/code-generation-summary.md` after Terra review and independent validation.

Summary must distinguish created and modified files, list checks/results, state unverified credential/device requirements, and record security compliance.

## Tests

### Exact test files and cases

- `scripts/test_release.py`: version grammar/bounds/code, names, checksums, manifest success/failures, aliases, notes, workflow policy, direct links, and secret-name policy.
- Existing Android unit suite proves debug/test configuration remains usable.
- Existing Swift suite proves version injection/package-script edits do not regress BridgeCore.

### Exact approved checks and working directories

Run from repository root unless a command contains its own `cd`:

1. `python3 -m unittest scripts/test_release.py`
2. `bash -n scripts/make-dmg.sh mac/scripts/make-macos-app.sh install.sh`
3. `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release-macos.yml")'`
4. `cd android && ./gradlew :app:testDebugUnitTest --no-daemon`
5. `cd mac && swift test`
6. `NO_INSTALL=1 mac/scripts/make-macos-app.sh`

No approved check invokes Git, Pi, Claude, destructive filesystem operations, or `.git` paths.

## Constraints and explicit exclusions

- Preserve every pre-existing modified and untracked file. Do not revert, overwrite, or clean unrelated work.
- Preserve the existing local Mac identity continuity behavior and current Calendar permission additions.
- No runtime updater code in DDP1.
- No marketplace, Apple notarization, Developer ID purchase, Intel artifact, Android below 13, debug public APK, silent installer, external updater framework, npm/Homebrew package, protocol change, hosted service, branch operation, worktree, history rewrite, or force push.
- Do not publish, commit, or push during Terra execution.
- Security requirements remain mandatory despite skipped NFR stages.

## Definition of done

- All Steps 1 through 9 implemented in exact approved files.
- All approved checks selected by Terra pass or unresolved failures are reported exactly.
- Sol reads every changed file and full diff, independently reruns relevant checks, and resolves at most one Terra-caused repair cycle.
- DDP1 summary exists and plan checkboxes are current.
- No release is published until DDP2/DDP3 and integrated Build and Test are complete.

## Coder restrictions

Terra may edit or write only the exact files exported in `PI_DEVELOP_FILES_JSON` and select only the listed approved checks. It must not plan, add files, author shell commands, make Git calls, access or edit `.git`, commit, push, create or switch branches, create worktrees, merge, rebase, reset, restore, clean, publish, release, or deliver. It must preserve all pre-existing content not explicitly changed by this brief and fail rather than invent an unresolved API or tool choice.

Exact approved files JSON:

`["VERSION","scripts/release.py","scripts/test_release.py","scripts/make-dmg.sh","mac/distribution-signing-requirement.txt","mac/scripts/make-macos-app.sh","android/app/build.gradle.kts",".github/workflows/release-macos.yml",".github/release-notes-template.md","README.md","docs/RELEASING.md","install.sh","mac/Sources/BridgeApp/SetupWizardView.swift"]`

Exact approved checks JSON:

`["python3 -m unittest scripts/test_release.py","bash -n scripts/make-dmg.sh mac/scripts/make-macos-app.sh install.sh","ruby -e 'require \"yaml\"; YAML.load_file(\".github/workflows/release-macos.yml\")'","cd android && ./gradlew :app:testDebugUnitTest --no-daemon","cd mac && swift test","NO_INSTALL=1 mac/scripts/make-macos-app.sh"]`

## Return format

Return only:

1. Changed files, separated into created and modified.
2. Implementation summary mapped to Steps 1 through 9.
3. Approved checks selected, exact results, and concise failure output.
4. Unresolved failures, missing credentials, or environment blockers.

Do not claim commit, push, publication, delivery, or checks not actually run.
