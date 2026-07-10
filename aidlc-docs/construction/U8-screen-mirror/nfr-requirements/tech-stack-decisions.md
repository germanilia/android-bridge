# Tech Stack Decisions — U8 Screen Mirror

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Capture (Android)** | `MediaProjection` + virtual display | Generic public API (NFR-6.1); per-session consent (US-7.2). |
| **Encode (Android)** | `MediaCodec` H.264/H.265 (hardware) | Low-latency hardware encode; codec selectable via `CaptureConfig` (FR-7.1). |
| **Decode/render (Mac)** | Swift `VideoToolbox` + AppKit/SwiftUI view | Native hardware decode; live view hosted by U11 shell. |
| **Transport** | U1 `FrameCodec` binary streams over U3 mTLS | Reuse the shared protocol; no new transport (NFR-6.2). |
| **Adaptive bitrate** | Pure `AdaptiveBitrateController` (Kotlin + Swift) | Side-effect-free control loop; the unit's PBT surface. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing**; Swift → **dependency-free seeded harness** | See environment deviation below. |
| **Dependency pinning (SECURITY-10)** | Gradle version catalog + lockfile; SPM `Package.resolved` | Exact versions; scan + SBOM at Build & Test. |

## Environment deviation (recorded)
This machine has **only the Swift Command Line Tools (no Xcode)**, so **XCTest and SwiftCheck are
unavailable**. The Swift side uses the project's **dependency-free seeded property-test harness**
(`protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift` + the `ProtocolCheck` runner,
invoked via `swift run`). The harness satisfies **PBT-09 intent** — custom generators, shrinking-lite,
and seeded reproducibility. On a machine **with Xcode**, swap the Swift PBT to **SwiftCheck + XCTest**.
Kotlin/JVM uses **Kotest Property Testing** for the adaptive-bitrate invariants.

## Notes
- The bitrate controller is duplicated in spirit across both languages (pure logic) and tested in each.
- Hardware codec performance (the NFR-3.1 latency target) is measured on real devices, not CI-gated.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
