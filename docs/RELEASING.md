# Releasing Android Bridge

## Protected GitHub Actions secrets

Configure these names in GitHub Actions. Never commit their values or decoded files:

- `MACOS_SIGNING_P12`
- `MACOS_SIGNING_PASSWORD`
- `ANDROID_RELEASE_KEYSTORE_B64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

## Android release key continuity

Create one dedicated keystore once with `keytool -genkeypair`; choose your own alias, passwords, and secure key parameters. Store an encrypted offline backup of the keystore and its recovery instructions separately from GitHub. Restore it into a disposable environment and build a release APK before relying on the backup.

The release key must remain available and unchanged. If it is lost, existing sideloaded installs cannot be upgraded in place. There is no practical in-place signing-key rotation for those installs: users must uninstall and install an APK signed by the replacement key.

## Mac signing continuity

`MACOS_SIGNING_P12` contains the stable Mac signing identity used for public packages. Keep its P12 and password in encrypted offline backup, and use the same identity for every update. Local developer builds keep their existing designated-requirement continuity; public packaging passes `mac/distribution-signing-requirement.txt` to enforce the distribution identity.

The current identity is not Developer ID notarized. A future paid Developer ID migration requires a deliberate identity/update migration plan, notarization with Apple, and revised public installation guidance.

## Channels

A push to `main` builds the rolling prerelease. It stages and verifies a complete commit-specific release before replacing `latest-build`; its assets use predictable `latest` names.

For a stable release, first set `VERSION` to the intended `MAJOR.MINOR.PATCH`, run the local checks, then create a matching `vMAJOR.MINOR.PATCH` tag. Stable releases are create-once. They publish versioned canonical assets and byte-identical DMG/APK aliases for `/releases/latest/download/` links. The manifest references only canonical versioned files.

## Local non-publishing checks

Run from the repository root:

```bash
python3 -m unittest scripts/test_release.py
bash -n scripts/make-dmg.sh mac/scripts/make-macos-app.sh install.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release-macos.yml")'
cd android && ./gradlew :app:testDebugUnitTest --no-daemon
cd mac && swift test
NO_INSTALL=1 mac/scripts/make-macos-app.sh
```

Production DMG and release APK validation additionally requires the protected signing inputs, an Apple Silicon Mac, and Android build-tools 34. These commands do not publish a release.
