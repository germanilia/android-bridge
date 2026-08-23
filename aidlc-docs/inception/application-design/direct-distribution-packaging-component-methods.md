# Direct distribution packaging component methods

Signatures are application-design contracts. Functional Design will define detailed rules and error cases before code generation.

## Shared release tooling

### Version and manifest tooling

- `read_version(path: Path) -> SemanticVersion`
- `derive_android_version_code(version: SemanticVersion) -> int`
- `validate_tag(version: SemanticVersion, tag: str) -> None`
- `sha256(path: Path) -> str`
- `apk_signer_sha256(apk: Path) -> str`
- `build_manifest(version: SemanticVersion, macos: ArtifactInput, android: AndroidArtifactInput) -> dict[str, object]`
- `validate_manifest(manifest: dict[str, object], artifact_root: Path) -> None`

Tooling exits non-zero with a specific diagnostic when input, signing, integrity, or package validation fails.

## Swift BridgeCore

### `SemanticVersion`

- `public init(_ value: String) throws`
- `public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool`
- `public var description: String { get }`

### `ReleaseArtifact`

- `public func validate() throws`

### `ReleaseManifest`

- `public func validate(for platform: ReleasePlatform) throws`
- `public var semanticVersion: SemanticVersion { get throws }`

### `ReleaseFetching`

- `public func latestStableRelease() async throws -> ReleaseBundle`

### `GitHubReleaseClient`

- `public init(session: URLSession = .shared)`
- `public func latestStableRelease() async throws -> ReleaseBundle`

### `ArtifactDownloading`

- `public func download(_ asset: ReleaseAsset, to directory: URL) async throws -> URL`

### `MacUpdateService`

- `public init(releases: any ReleaseFetching, downloader: any ArtifactDownloading)`
- `public func check(currentVersion: String) async throws -> MacUpdate?`
- `public func downloadAndVerify(_ update: MacUpdate) async throws -> URL`
- `public func removeTemporaryUpdate(at url: URL) throws`

## Swift BridgeApp

### `MacUpdateController`

- `@MainActor init(service: MacUpdateService)`
- `@MainActor func checkAfterLaunch()`
- `@MainActor func checkManually()`
- `@MainActor func confirmAndDownload(_ update: MacUpdate)`
- `@MainActor func openVerifiedDMG(_ url: URL)`

The controller owns presentation state. BridgeCore owns network, parsing, comparison, download, and integrity rules.

## Kotlin core

### `SemanticVersion`

- `constructor(value: String)`
- `override fun compareTo(other: SemanticVersion): Int`
- `override fun toString(): String`

### `ReleaseArtifact`

- `fun validate()`

### `ReleaseManifest`

- `fun validate(platform: ReleasePlatform)`
- `fun semanticVersion(): SemanticVersion`

### `ReleaseSource`

- `suspend fun latestStableRelease(): ReleaseBundle`

### `GitHubReleaseClient`

- `suspend fun latestStableRelease(): ReleaseBundle`

### `ArtifactDownloader`

- `suspend fun download(asset: ReleaseAsset, directory: File): File`

### `AndroidUpdateService`

- `suspend fun check(currentVersionName: String, currentVersionCode: Int): AndroidUpdate?`
- `suspend fun downloadAndVerify(update: AndroidUpdate, directory: File): File`
- `fun cleanTemporaryUpdates(directory: File)`

## Kotlin Android integration

### `ApkSignatureVerifier`

- `fun verify(apk: File, expectedFingerprint: String)`
- `fun installedSignerSha256(): String`
- `fun archiveSignerSha256(apk: File): String`

### `ApkInstaller`

- `fun install(apk: File)`

### `MainActivity`

Existing entry point preserved: `override fun onCreate(savedInstanceState: Bundle?)`.

New private integration methods:

- `private fun checkForUpdates(manual: Boolean)`
- `private fun confirmUpdate(update: AndroidUpdate)`
- `private fun downloadAndInstall(update: AndroidUpdate)`

### Compose integration

Existing `HomeScreen(...)` remains the app-level composable and gains update state plus callbacks:

- `onCheckForUpdates: () -> Unit`
- `onAcceptUpdate: (AndroidUpdate) -> Unit`
- `onDismissUpdate: () -> Unit`

## Error contract

- Parsing, network, release-selection, validation, download, checksum, and signer failures use typed domain errors.
- UI controllers map typed failures to actionable text.
- No component catches and suppresses an update-security failure.
- Cancellation is distinct from failure and removes partial downloads without reporting installation success.
