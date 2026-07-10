# Tech Stack Decisions — U7 Clipboard

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Languages** | Swift (`mac/Plugins/Clipboard`) + Kotlin (`android/.../feature` + plugin) | Native to each app; reuse shared U1 control contract. |
| **Clipboard access** | Platform-native — Android `ClipboardManager` · Mac `NSPasteboard` | Standard OS APIs; no third-party clipboard deps. |
| **Control messages** | `clip.update` via U1 `MessageCodec` + `Mappers.clipboard` | Length-prefixed JSON, validated against the type registry. |
| **Sync policy** | Pure `ClipboardSyncPolicy` (MANUAL default, AUTO opt-in) | Decision logic kept free of platform types → JVM/Swift testable. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing** · Swift → seeded harness (see deviation) | Custom generators (text/mode), shrinking, seed reproducibility. |
| **Unit test runner** | Kotlin → **JUnit5 + Kotest** · Swift → `swift run …Check` harness | Current-gen runner on Kotlin; Swift uses the dependency-free harness below. |
| **Build / dependency mgmt** | SwiftPM · Gradle (version catalog) | Per ecosystem; `protocol/` consumed by both. |
| **Dependency pinning (SECURITY-10)** | `Package.resolved` + Gradle catalog/lockfile committed | Exact versions; scanning + SBOM at Build & Test. |

## Environment-forced deviation (Swift testing)
This machine has **only the Swift Command Line Tools (no Xcode)**, so **XCTest and SwiftCheck are
unavailable**. The Swift side uses the **dependency-free, seeded property-test harness**
(`protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift`, run via `swift run ProtocolCheck`)
instead of SwiftCheck/XCTest. This meets PBT-09's intent — custom generators, shrinking-lite, seeded
reproducibility (PBT-08). With Xcode present you would swap to **SwiftCheck + XCTest** with no change
to the properties. Kotlin uses Kotest property testing normally.

## PBT framework verification (PBT-09)
- ✅ Custom generators — clipboard text (empty/Unicode/boundary) + `(mode, userInitiated)` pairs.
- ✅ Shrinking — Kotest default; Swift harness shrinks-lite + replays via logged seed.
- ✅ Seed-based reproducibility — Kotest seed; Swift harness prints seed + iteration on failure.
- ✅ Runner integration — Kotest ↔ JUnit5; Swift harness ↔ `swift run`.

## Notes
- No runtime third-party dependencies beyond platform clipboard APIs.
- Sync-mode setting persistence is delegated to U10 (SecureStore/settings).

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
