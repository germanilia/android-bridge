# Tech Stack Decisions — U11 Mac App Shell

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Language / UI** | Swift 5.9/6 + **SwiftUI** | Native macOS menu-bar + windows; Continuity-class polish (NFR-4.x). |
| **App structure** | `MenuBarExtra` + `WindowGroup`s, MVVM (`ObservableObject` view-models) | Menu-bar-first; thin views, logic in services (BR-6). |
| **Build / packaging** | Swift Package Manager; the macOS app target requires **Xcode** to build/run | App bundles, entitlements, and `MenuBarExtra` need the Xcode toolchain. |
| **Protocol dependency** | `protocol/swift` (DeviceLinkProtocol) via SPM | Shared codec/registry consumed by the Mac Core/plugins. |
| **Notifications** | `UserNotifications` (native macOS) | Mirrored notifications (U4) + caller-ID (U9) feel native. |
| **Secure storage** | macOS **Keychain** (via U2 SecureStore) | Encryption at rest for trust material/settings (SECURITY-01/-12) — owned by U2/U10. |
| **PBT framework (PBT-09)** | N/A for the shell | No properties identified (PBT-01); UI tested by example/UI tests (PBT-10). |

## Environment deviation (recorded — must carry to Build & Test)
- **This machine has only the Swift Command Line Tools (no Xcode).** A SwiftUI macOS **app target
  cannot be built or run here** — it needs Xcode (app bundle, entitlements, `MenuBarExtra`). The only
  Swift code that builds/tests in this environment is the dependency-free `protocol/swift` package
  (`swift build`, `swift run ProtocolCheck`).
- Consequently the Mac shell is **design-only** in this environment; building it requires a machine with
  Xcode + the macOS SDK.
- Where Swift property tests are relevant (shared protocol), the repo uses the **dependency-free seeded
  harness** (`PropertyHarness.swift` + `ProtocolCheck`) in place of XCTest/SwiftCheck (PBT-09 intent
  met); swap to SwiftCheck + XCTest on a machine with Xcode.

## Notes
- Dependency pinning via committed `Package.resolved`; scan + SBOM at Build & Test (SECURITY-10).
- No third-party UI frameworks — SwiftUI + the shared protocol package only (minimal supply-chain surface).

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
