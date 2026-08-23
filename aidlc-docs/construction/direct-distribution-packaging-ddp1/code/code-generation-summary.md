# DDP1 code-generation summary

## Result

DDP1 release packaging and signing implementation is complete locally. Stable and rolling publication code exists, but no GitHub Release was published in this unit because DDP2, DDP3, integrated Build and Test, repository credentials, and Android release secrets still gate delivery.

## Created

- `VERSION`
- `scripts/release.py`
- `scripts/test_release.py`
- `scripts/make-dmg.sh`
- `mac/distribution-signing-requirement.txt`
- `.github/release-notes-template.md`
- `docs/RELEASING.md`

## Modified

- `android/app/build.gradle.kts`
- `mac/scripts/make-macos-app.sh`
- `.github/workflows/release-macos.yml`
- `README.md`
- `install.sh`
- `mac/Sources/BridgeApp/SetupWizardView.swift`

All pre-existing changes in `mac/scripts/make-macos-app.sh` and the rest of the working tree were preserved.

## Implemented behavior

- Root `0.1.0` version with derived build/version code `1000`.
- Strict version, artifact-name, checksum, manifest, CycloneDX, alias, and release-note validation.
- Android release signing from four required environment variables with clear fail-closed missing-input diagnostics.
- Mac public distribution requirement pinned to the existing `Android Bridge Distribution` identity.
- Version injection into Android and Mac production metadata.
- Verified read-only UDZO DMG with `AndroidBridge.app` and Applications symlink.
- Stable versioned artifacts plus predictable byte-identical direct-download aliases.
- Rolling predictable artifact names.
- Immutable GitHub Action revisions, read-only build permission, publication-only write permission, pinned Syft `1.51.0`, and pinned Grype `0.117.0` with high-severity failure.
- Recoverable staged rolling publication and create-once stable publication.
- Stable DMG/APK links, Gatekeeper-safe guidance, advanced rolling installer, and maintainer signing/release guide.
- Public packages exclude the developer-local 1.1 GB MLX virtual environment; Setup Wizard remains responsible for managed installation on user machines.

## Terra execution

- **Parent model**: `gpt-5.6-sol`.
- **Coder model**: `openai-codex/gpt-5.6-terra`.
- **Guard**: Pi Develop deny-git extension with 13 exact files and six exact checks.
- **Initial Terra checks**: six passed.
- **Focused repair**: one repair invocation fixed workflow directory state, stable download URLs, deterministic DMG mounting, installer identity enforcement, APK signer counting, rolling tag recovery, and CycloneDX validation.
- **Repair checks**: Python tests, shell syntax, and YAML parsing passed.

## Sol review and independent validation

- Read every DDP1 implementation file and reviewed the complete DDP1 diff.
- Preserved unrelated tracked and untracked work.
- Fixed action-artifact directory shape, release CLI boundary handling, large-alias memory use, workflow temporary-keychain cleanup, rolling tag edge cases, local-tool exclusion for public packages, and executable mode.
- `python3 -m unittest scripts/test_release.py`: 7 tests passed.
- `bash -n scripts/make-dmg.sh mac/scripts/make-macos-app.sh install.sh`: passed.
- Ruby YAML parse: passed; local Ruby warned that the Android SDK directory is world-writable.
- `actionlint .github/workflows/release-macos.yml`: passed.
- `cd android && ./gradlew :app:testDebugUnitTest --no-daemon`: passed.
- `cd mac && swift test`: 40 XCTest tests plus three 100-case property checks passed.
- `NO_INSTALL=1 mac/scripts/make-macos-app.sh`: passed with local identity.
- Missing Android signing variables: release build failed closed and named all four required variables.
- Version metadata: root, Mac short version, and numeric build version matched `0.1.0` and `1000`.
- Public identity Mac build: passed with the exact distribution requirement.
- `scripts/make-dmg.sh`: produced, mounted, verified, and detached a UDZO read-only test DMG.
- `git diff --check`: passed.
- Approved-file secret marker scan: passed.

## Security extension compliance

| Rule | Status | Evidence |
|---|---|---|
| SECURITY-06 | Compliant | Build job read-only; publish job alone has contents write. |
| SECURITY-09 | Compliant | Supported platform minimums, fixed runner, JDK 17, Gradle wrapper, and lock files. |
| SECURITY-10 | Compliant locally | Immutable action SHAs, pinned Syft/Grype, CycloneDX generation, and high-severity gate configured. CI execution remains pending. |
| SECURITY-12 | Compliant | Secret names only in source/docs; temporary credential paths and cleanup; no embedded values. |
| SECURITY-13 | Compliant locally | DMG signature/requirement, APK signer extraction, SHA-256, manifest, and alias validation. Signed APK execution remains pending. |
| SECURITY-15 | Compliant locally | Missing inputs and validation failures stop publication; rolling rollback is encoded; installed-app identity replacement is refused. Remote recovery remains pending CI validation. |

Other security baseline rules are not applicable to DDP1. No local blocking finding remains.

## Remaining external validation

- Configure or confirm all six GitHub Actions signing secrets.
- Build a release APK with the long-lived Android key and verify its certificate.
- Execute Syft and Grype in GitHub Actions.
- Exercise rolling promotion and rollback against GitHub Releases.
- Complete DDP2 and DDP3 before final stable publication.
