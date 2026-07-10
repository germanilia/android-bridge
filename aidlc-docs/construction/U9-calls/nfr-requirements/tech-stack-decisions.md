# Tech Stack Decisions — U9 Calls

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Call observation (Android)** | `InCallService` / `TelephonyManager` | Generic public APIs (NFR-6.1); no Samsung deps. |
| **Call actuation (Android)** | `InCallService` (answer/decline) + `ACTION_CALL` dial | Public telephony APIs for answer/decline/dial (US-8.3/8.4). |
| **Contact resolution** | Android Contacts provider (read perm) | Resolve name/photo only if granted (US-8.2, FR-8.7). |
| **Call audio** | **Bluetooth HFP at the OS level — not in the app/protocol** | Android has no live call-audio API without root (FR-8.4); paired once in onboarding. |
| **Mac UI** | SwiftUI caller-ID popup + controls + history (U11) | Native menu-bar-first experience. |
| **Wire mapping** | `Mappers` (`call.incoming`/`call.action`/`call.history`) | Pure, JVM-testable; reuse the shared protocol. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing**; Swift → **dependency-free seeded harness** | See environment deviation below. |
| **Dependency pinning (SECURITY-10)** | Gradle version catalog + lockfile; SPM `Package.resolved` | Exact versions; scan + SBOM at Build & Test. |

## Environment deviation (recorded)
This machine has **only the Swift Command Line Tools (no Xcode)**, so **XCTest and SwiftCheck are
unavailable**. The Swift side uses the project's **dependency-free seeded property-test harness**
(`protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift` + the `ProtocolCheck` runner via
`swift run`). It satisfies **PBT-09 intent** — custom generators, shrinking-lite, seeded reproducibility.
On a machine **with Xcode**, swap the Swift PBT to **SwiftCheck + XCTest**. Kotlin/JVM uses **Kotest
Property Testing** for the `Mappers` round-trips, number-normalization, and action-allowlist invariants.

## Notes
- The `Mappers` and `normalize` functions are pure and the only PBT surface; all telephony/Bluetooth code
  is device IO verified on real hardware.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
