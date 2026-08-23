# DDP2 macOS update client code-generation plan

## Approval

Approved for autonomous end-to-end generation by the user instruction `so make it ready`. This file is the single source of truth for DDP2 Code Generation.

## Unit context

- **Owner**: DDP2 macOS update client.
- **Requirements**: FR-06; Mac runtime portions of FR-03, FR-05, FR-08; NFR-01 through NFR-05; AC-06 through AC-08.
- **Dependency**: frozen DDP1 schema-1 manifest and canonical versioned DMG/checksum assets.
- **Boundary**: BridgeCore owns networking, decoding, comparison, download, integrity, and cleanup. BridgeApp owns consent, status, native open, Finder reveal, and installation guidance.
- **Database entities**: none.
- **Exclusions**: no silent replacement, Sparkle/external updater, protocol changes, alternate repository/channel, Git action, or publication logic.

## Exact implementation files

1. `mac/Sources/BridgeCore/MacUpdate.swift` — new typed release/update core.
2. `mac/Tests/BridgeCoreTests/MacUpdateTests.swift` — new example-based tests.
3. `mac/Sources/BridgeApp/MacUpdateController.swift` — new main-actor presentation controller.
4. `mac/Sources/BridgeApp/main.swift` — modify existing AppDelegate construction/startup/termination.
5. `mac/Sources/BridgeApp/BridgeApp.swift` — modify existing dashboard and Settings integration.

## Ordered generation steps

### Step 1: Tests-first contract

- [x] Create Swift tests for strict semantic versions, numeric ordering, exact schema/tag/asset binding, update/no-update decisions, checksum acceptance, checksum rejection, size/digest rejection, and temporary cleanup.
- [x] Use fakes conforming to exact production protocols; no live GitHub or AppKit in tests.

### Step 2: BridgeCore models and errors

- [x] Add `SemanticVersion`, GitHub Release/asset DTOs, exact schema-1 manifest descriptors, `ReleaseBundle`, `MacUpdate`, `VerifiedMacUpdate`, and typed `MacUpdateError`.
- [x] Validate exact keys with `JSONSerialization` before typed decoding; reject extra/missing keys, malformed hashes, mismatched version code, platform minimum, tag, asset name, asset size, and duplicate assets.

### Step 3: Stable Release client

- [x] Add `ReleaseFetching` and production `GitHubReleaseClient` using Foundation `URLSession`.
- [x] Fix discovery to `https://api.github.com/repos/germanilia/android-bridge/releases/latest`.
- [x] Require HTTPS, approved GitHub hosts, fixed repository/tag/name paths, HTTP 200, bounded Release/manifest bodies, stable tag, and same-Release assets.
- [x] Follow only HTTPS redirects to fixed GitHub release-asset hosts.

### Step 4: Download and integrity service

- [x] Add `ArtifactDownloading`, production streaming downloader, and `MacUpdateService`.
- [x] `check(currentVersion:)` returns only a strictly newer validated update.
- [x] `downloadAndVerify(_:)` creates one owned temporary directory, fetches the exact checksum after consent, streams the DMG with a hard byte limit, verifies exact size and SHA-256 with existing Crypto dependency, and returns `VerifiedMacUpdate` only after agreement.
- [x] Delete partial/rejected data and expose narrow cleanup for updater-owned paths.

### Step 5: Native controller

- [x] Add `@MainActor MacUpdateController` with one automatic check per launch, shared manual discovery, consent-gated download, cancellation, safe typed messages, verified-only `NSWorkspace.open`, Finder reveal on open failure, and termination cleanup.
- [x] Automatic no-update/network failure remains non-modal; manual checks always produce status.

### Step 6: Existing AppDelegate integration

- [x] Construct one production controller in `AppDelegate`.
- [x] Pass it to the existing `DashboardView`, start the check only after normal dashboard rendering, and clean up on application termination.
- [x] Preserve all existing menus, link startup, windows, and unrelated modified code.

### Step 7: Existing SwiftUI integration

- [x] Extend `DashboardView` and `SettingsTab` in place with one observed controller.
- [x] Add a Software Update Settings section, update consent dialog, download progress, result/error presentation, release-page link, and non-notarized drag-to-Applications/Control-click guidance.
- [x] Use native accessible SwiftUI controls; no web UI or automation-only attributes that SwiftUI does not support.

### Step 8: Validation and summary

- [x] Run all approved checks.
- [x] Verify no duplicate brownfield files, no live network in tests, no raw unverified URL reaches AppKit, and no unrelated changes are removed.
- [x] Create `aidlc-docs/construction/direct-distribution-packaging-ddp2/code/code-generation-summary.md` after Sol review.

## Exact approved checks

1. `cd mac && swift test`
2. `cd mac && swift build`
3. `NO_INSTALL=1 mac/scripts/make-macos-app.sh`

## Implementation anchors

Existing signatures preserved:

- `func applicationDidFinishLaunching(_ notification: Notification)`
- `@objc func openDashboard()`
- `struct DashboardView: View`
- `struct SettingsTab: View`

Target core interfaces:

```swift
public protocol ReleaseFetching {
    func latestStableRelease() async throws -> ReleaseBundle
}

public protocol ArtifactDownloading {
    func data(from asset: ReleaseAsset, maximumBytes: Int) async throws -> Data
    func download(_ asset: ReleaseAsset, to directory: URL, maximumBytes: Int64) async throws -> URL
}

public final class MacUpdateService {
    public func check(currentVersion: String) async throws -> MacUpdate?
    public func downloadAndVerify(_ update: MacUpdate) async throws -> VerifiedMacUpdate
    public func removeTemporaryUpdate(_ update: VerifiedMacUpdate) throws
}
```

## Error policy

- External JSON, HTTP, redirect, filesystem, and downloaded bytes are real validation boundaries.
- Fail closed with typed errors; never broad-catch into success or silently accept defaults.
- UI maps typed errors to safe actionable messages; automatic transient failures may be quiet but remain status-visible.
- Partial and rejected data is removed. Installed app and user data are never mutated.

## Coder restrictions

Terra may edit/write only the five exact implementation files and select only the three approved checks. No Git, `.git`, branch, worktree, commit, push, release, package publication, shell authoring, or unrelated refactor.
