# Tech Stack Decisions — U1 Protocol / Transport core

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Languages** | Swift (`protocol/swift`) + Kotlin (`protocol/kotlin`) | Native to each app; hand-written codecs kept in sync with `PROTOCOL.md` (Q2/Q3 of Units stage). |
| **Control serialization** | UTF-8 JSON, 4-byte BE length prefix | Decided in U1 Functional Design (BR-1); debuggable + easy round-trip. |
| **JSON library** | Platform-native — Swift `Codable`/`JSONEncoder` · Kotlin `kotlinx.serialization` | No third-party JSON dep; `kotlinx.serialization` is the idiomatic, compile-time-safe Kotlin choice. |
| **PBT framework (PBT-09)** | Swift → **SwiftCheck** · Kotlin → **Kotest Property Testing** | Both support custom generators, automatic shrinking, seed-based reproducibility (Q1). |
| **Unit test runner** | Swift → **swift-testing** · Kotlin → **JUnit5 + Kotest** | Current-gen runners; SwiftCheck/Kotest integrate cleanly (Q2). |
| **Build / dependency mgmt** | Swift Package Manager · Gradle (Kotlin, version catalog) | Standard per ecosystem; `protocol/` consumed by `mac/` and `android/`. |
| **Dependency pinning (SECURITY-10)** | SPM `Package.resolved` committed · Gradle version catalog + dependency lockfile committed | Exact versions; no `latest`. Scanning + SBOM handled at Build & Test (Q4). |

## PBT framework verification (PBT-09)
- ✅ Custom generators for domain types — SwiftCheck `Arbitrary`, Kotest `Arb` for `Message`, `MessageType`, `FrameHeader`, payloads.
- ✅ Automatic shrinking — both frameworks shrink to minimal failing input by default (PBT-08).
- ✅ Seed-based reproducibility — both expose/log seeds; CI will log seed per run (PBT-08).
- ✅ Test-runner integration — SwiftCheck ↔ swift-testing/XCTest; Kotest ↔ JUnit5.
- ✅ Declared as project dependencies in `protocol/swift` (SPM) and `protocol/kotlin` (Gradle).

## Notes
- No runtime third-party dependencies for the codec itself (only platform JSON) — minimizes supply-chain surface.
- Performance target (NFR-U1.2) verified with a lightweight benchmark in each language, not a CI gate.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
