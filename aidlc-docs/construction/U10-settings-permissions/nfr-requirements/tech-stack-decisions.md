# Tech Stack Decisions — U10 Settings & Permissions

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Languages** | Swift (Mac) + Kotlin (Android) | Native per app; `FeatureId`/effective-state logic mirrored, OS-permission adapters per platform. |
| **Toggle registry** | `PluginRegistry` (pure, in-memory) seeded from persisted snapshot | Already scaffolded in `core/PluginRegistry.kt`; pure → JVM-testable. |
| **Permission APIs** | Platform-native — Android runtime/ special-access grants (`NotificationListenerService`, `MediaProjection`, runtime perms); macOS TCC / `CBCentralManager` / Local Network | Generic public APIs only (NFR-6.1); no Samsung-specific grants. |
| **Persistence** | `SecureStore` (Keychain on Mac / Keystore + EncryptedSharedPreferences on Android) | Encrypted at rest (SECURITY-01/-12); `AndroidSecureStore.kt` already implements the Android side. |
| **Settings serialization** | `kotlinx.serialization` (Kotlin) · `Codable` (Swift) | Same native JSON stack as U1; snapshot round-trip is the PBT-02 surface. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing** · Swift → seeded harness (see note) | Effective-state + snapshot round-trip properties. |

## Environment deviation (recorded — must carry to Build & Test)
- This machine has **only the Swift Command Line Tools (no Xcode)**, so **XCTest and SwiftCheck are
  unavailable**. The Swift side uses the repo's **dependency-free, seeded property-test harness**
  (`protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift` + the `ProtocolCheck` target,
  run via `swift run ProtocolCheck`). It provides custom generators, shrinking-lite, and seeded
  reproducibility — meeting the **intent of PBT-09**. On a machine with Xcode you would swap to
  **SwiftCheck + XCTest** with no change to the properties.
- Kotlin/JVM uses **Kotest property testing** (`io.kotest:kotest-property`) — already a dependency.

## Notes
- No runtime third-party dependency for the toggle/effective-state logic — only platform JSON + secure
  storage (`androidx.security:security-crypto` on Android, Keychain on Mac).
- Dependency pinning (`Package.resolved` / Gradle version catalog + lockfile) + scan + SBOM are handled
  project-wide at Build & Test (SECURITY-10).

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
