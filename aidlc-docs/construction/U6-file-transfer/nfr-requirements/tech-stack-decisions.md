# Tech Stack Decisions — U6 File Transfer

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Languages** | Swift (`mac/Plugins/FileTransfer`) + Kotlin (`android/.../feature` + plugin) | Native to each app; reuse the shared U1 framing contract. |
| **Bulk transport** | U1 `Frame`/`FrameHeader` + `StreamChunker`/`StreamReassembler` over U3 `openStream` | No new wire format; 64 KiB chunks, ordering invariant inherited from U1. |
| **Control messages** | `file.offer` / `file.accept` / `file.progress` via U1 `MessageCodec` | Length-prefixed JSON; validated against the type registry. |
| **File I/O** | Platform-native — Swift `FileManager` / Foundation streams · Kotlin `java.io` / `OutputStream` | Standard, no third-party file deps; atomic temp+rename writes. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing** · Swift → seeded harness (see deviation) | Custom generators (byte arrays/sizes), shrinking, seed reproducibility. |
| **Unit test runner** | Kotlin → **JUnit5 + Kotest** · Swift → `swift run …Check` harness | Current-gen runner on Kotlin; Swift uses the dependency-free harness below. |
| **Build / dependency mgmt** | SwiftPM · Gradle (version catalog) | `protocol/` consumed by both; pinned per ecosystem. |
| **Dependency pinning (SECURITY-10)** | `Package.resolved` + Gradle catalog/lockfile committed | Exact versions; scanning + SBOM at Build & Test. |

## Environment-forced deviation (Swift testing)
This machine has **only the Swift Command Line Tools (no Xcode)**, so **XCTest and SwiftCheck are
unavailable**. The Swift side therefore uses the **dependency-free, seeded property-test harness**
(`protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift`, driven via
`swift run ProtocolCheck`) instead of SwiftCheck/XCTest. This meets PBT-09's intent — custom
generators, shrinking-lite, and seeded reproducibility (PBT-08). On a machine with Xcode you would
swap to **SwiftCheck + XCTest** with no change to the properties under test. Kotlin uses Kotest
property testing normally.

## PBT framework verification (PBT-09)
- ✅ Custom generators — byte arrays across boundary sizes (empty / sub-chunk / multiple / non-multiple of 64 KiB).
- ✅ Shrinking — Kotest default; Swift harness shrinks-lite + replays via logged seed.
- ✅ Seed-based reproducibility — Kotest seed; Swift harness prints seed + iteration on failure.
- ✅ Runner integration — Kotest ↔ JUnit5; Swift harness ↔ `swift run`.

## Notes
- No runtime third-party dependencies for the transfer core beyond platform file I/O.
- Throughput is LAN-bound; no benchmark gate beyond the U1 codec micro-benchmark (NFR-U1.2).

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
