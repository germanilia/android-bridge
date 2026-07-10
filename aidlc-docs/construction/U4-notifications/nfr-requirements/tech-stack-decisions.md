# Tech Stack Decisions — U4 Notifications

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Android capture** | `NotificationListenerService` (public API) | The only generic way to read posted notifications (US-10.3, no Samsung APIs). Requires the system "notification access" grant (U10). |
| **Mapping** | Pure Kotlin in `feature/Mappers.kt` (no Android types) | Keeps the OS→protocol transform JVM-testable (PBT). |
| **Allowlist persistence** | `SecureStore` (Keystore + EncryptedSharedPreferences) | Encrypted at rest; survives restart (FR-9.3 / SECURITY-01/-12). |
| **Mac render** | Native macOS `UNUserNotificationCenter` / feed (SwiftUI) | Native polish (NFR-4.x); built in U11. |
| **Serialization** | U1 codec — Kotlin `kotlinx.serialization`, Swift `Codable` | Reuses the shared envelope; no new JSON dep. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing**; Swift → seeded harness | See environment deviation below. |

## Environment deviation (PBT-09 / SECURITY-10)
- The Mac side is **Swift**, but this machine has only the **Swift Command Line Tools (no Xcode)**, so
  **XCTest and SwiftCheck are unavailable**. The Swift codec/PBT therefore use the project's
  **dependency-free seeded property-test harness** (`protocol/swift/.../PropertyHarness.swift`, run via
  `ProtocolCheck`). It provides domain generators, deterministic seeds, and shrinking-lite — satisfying
  PBT-09's intent. On a machine with Xcode, swap to **SwiftCheck + XCTest** with no design change.
- Kotlin uses **Kotest Property Testing** normally (`kotest-property`, pinned in `android/app/build.gradle.kts`).
- Dependency pinning + vulnerability scan + SBOM (SECURITY-10) are handled at **Build & Test**; U4 adds
  no new runtime dependency beyond the platform notification APIs.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
