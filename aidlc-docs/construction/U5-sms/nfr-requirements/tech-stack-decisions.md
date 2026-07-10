# Tech Stack Decisions — U5 SMS / MMS

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Android read** | Telephony content provider + SMS broadcast (public APIs) | Generic Android only (US-10.3, no Samsung APIs). RCS is excluded (FR-4.5). |
| **Mapping** | Pure Kotlin in `feature/Mappers.kt` (no Android types) | OS→protocol transform stays JVM-testable (PBT). |
| **Thread grouping** | Pure function `ConversationGrouping` (planned, JVM-testable) | Primary invariant PBT target (PBT-03). |
| **History/cache** | `SecureStore` (Keystore + EncryptedSharedPreferences) if cached | Encrypted at rest (SECURITY-01/-12). |
| **MMS bytes** | Inline ≤ 32 KiB else U6 frame stream | Reuses U1 framing (BR-5/BR-6); avoids a separate transport. |
| **Mac render** | SwiftUI Messages window (threaded) | Native polish (NFR-4.x); built in U11. |
| **Serialization** | U1 codec — Kotlin `kotlinx.serialization`, Swift `Codable` | Reuses the shared envelope; no new JSON dep. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing**; Swift → seeded harness | See environment deviation below. |

## Environment deviation (PBT-09 / SECURITY-10)
- The Mac side is **Swift**, but this machine has only the **Swift Command Line Tools (no Xcode)**, so
  **XCTest and SwiftCheck are unavailable**. The Swift codec/PBT use the project's **dependency-free
  seeded property-test harness** (`protocol/swift/.../PropertyHarness.swift`, run via `ProtocolCheck`):
  domain generators + deterministic seeds + shrinking-lite — satisfying PBT-09's intent. Swap to
  **SwiftCheck + XCTest** on a machine with Xcode, no design change.
- Kotlin uses **Kotest Property Testing** (`kotest-property`, pinned in `android/app/build.gradle.kts`).
- Dependency pinning + vulnerability scan + SBOM (SECURITY-10) are handled at **Build & Test**; U5 adds
  no new runtime dependency beyond the platform Telephony APIs.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
