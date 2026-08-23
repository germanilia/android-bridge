# Direct distribution packaging component dependencies

## Dependency direction

| Component | Depends on | Must not depend on |
|---|---|---|
| Root version source | Nothing | Platform UI or CI secrets |
| Release packaging scripts | Version source, built app/APK, native package tools | App runtime state |
| GitHub release workflow | Packaging scripts, GitHub Releases, signing secrets | Update-client implementation details |
| Shared manifest models | Foundation or Kotlin serialization | UI and installers |
| Semantic version | Standard language library | Network, filesystem, UI |
| GitHub release client | Manifest models, HTTPS client | Platform installer |
| Mac update service | Release source, downloader, hashing, temporary filesystem | AppKit or SwiftUI |
| Mac update controller | Mac update service, AppKit presentation and workspace | Android code or signing secrets |
| Android update service | Release source, downloader, hashing, signature-verifier interface | Compose UI |
| APK signature verifier | Android `PackageManager` | Network and GitHub APIs |
| APK installer | Android `FileProvider` and package-installer intent | Release parsing |
| Android update UI | Android update service and installer | GitHub workflow or secrets |

## Release data flow

1. `VERSION` supplies a validated semantic version.
2. Gradle and the Mac app bundler consume that version.
3. CI builds signed artifacts.
4. Packaging tooling computes artifact metadata and emits `release-manifest.json`.
5. Validation proves manifest and files agree.
6. GitHub Release publication uploads the manifest and all referenced assets together.
7. Runtime clients fetch the latest stable Release and its manifest.
8. Each client selects, downloads, and verifies only its platform artifact.
9. Platform UI requests confirmation and invokes the native installation handoff.

## macOS runtime flow

| Source | Target | Contract |
|---|---|---|
| `AppDelegate` or Settings | `MacUpdateController` | Automatic or manual check request |
| `MacUpdateController` | `MacUpdateService` | Current bundle version and user-approved download |
| `MacUpdateService` | `ReleaseFetching` | Latest validated stable release |
| `GitHubReleaseClient` | GitHub API | HTTPS JSON and manifest asset |
| `MacUpdateService` | `ArtifactDownloading` | DMG URL, expected size, and target directory |
| `MacUpdateService` | Hash verifier | Local DMG and expected SHA-256 |
| `MacUpdateController` | `NSWorkspace` | Verified local DMG URL only |

BridgeCore never imports AppKit. BridgeApp owns dialogs and opening the DMG.

## Android runtime flow

| Source | Target | Contract |
|---|---|---|
| `MainActivity` or Settings UI | `AndroidUpdateService` | Automatic or manual check request |
| `AndroidUpdateService` | `ReleaseSource` | Latest validated stable release |
| `GitHubReleaseClient` | GitHub API | HTTPS JSON and manifest asset |
| `AndroidUpdateService` | `ArtifactDownloader` | APK URL, expected size, and cache directory |
| `AndroidUpdateService` | Hash verifier | Local APK and expected SHA-256 |
| `AndroidUpdateService` | `ApkSignatureVerifier` | Local APK and expected signer fingerprint |
| `MainActivity` | `ApkInstaller` | Verified local APK only |
| `ApkInstaller` | Android package installer | Scoped content URI and read grant |

The installer never receives an unverified path. The verifier never initiates network traffic.

## Trust boundaries

| Boundary | Trusted input after validation | Rejected input |
|---|---|---|
| GitHub API | Latest stable release for the fixed repository | Draft, prerelease, other repository, malformed tag |
| Manifest | Supported schema and exact release-tag match | Unknown schema, malformed version, invalid hash or size |
| Download | HTTPS platform asset from same Release | Redirect or source violating host policy, wrong size, wrong digest |
| Android package | APK signed by installed certificate and manifest fingerprint | Missing, changed, multiple ambiguous, or mismatched signer |
| CI signing | Secret-backed temporary keystores | Checked-in keys, missing values, logged credentials |

## Change isolation

- Device-link protocol modules remain unchanged.
- Existing pairing, meetings, Second Brain, clipboard, file, screen, and call components do not depend on updater code.
- Existing app startup proceeds regardless of update-service availability.
- Release publication never runs from application runtime code.
