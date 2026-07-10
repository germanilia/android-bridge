# Tech Stack Decisions — U2 Pairing & Security

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Languages** | Kotlin (`android/app/.../core/Pairing.kt`) + Swift (`mac/`, Keychain-backed, not yet written) | Native per app; pure pairing logic kept platform-agnostic and JVM-testable. |
| **Asymmetric crypto** | **EC P-256** keypair (JDK `KeyPairGenerator("EC")` on Android; Security/CryptoKit on Mac) | Modern, compact, widely supported for TLS identities; basis for the per-device cert used by U3 mTLS. |
| **Fingerprint** | **SHA-256** of the public key bytes, `:`-joined hex | Standard cert-pinning fingerprint; self-checking inside the QR (BR-2). |
| **QR payload format** | Compact JSON via `kotlinx.serialization` (Kotlin) / `Codable` (Swift) | Same discipline as U1 envelope; round-trippable for PBT-02. |
| **Encrypted at rest** | Android **Keystore-derived MasterKey + EncryptedSharedPreferences** (`androidx.security:security-crypto`); Mac **Keychain** | OS-managed secure storage, no plaintext on disk (SECURITY-01/-12). |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing**; Swift → seeded `PropertyHarness` (see deviation) | Custom generators, shrinking, seed reproducibility for QR/fingerprint/list properties. |
| **Dependency pinning (SECURITY-10)** | Gradle version catalog + lockfile; SPM `Package.resolved` | Exact versions; scan + SBOM at Build & Test. |

## Environment deviation (no Xcode on this machine)
This machine has only **Swift Command Line Tools** — **XCTest and SwiftCheck are unavailable**. The
Swift side therefore uses the dependency-free, seeded property-test harness
(`protocol/swift/Sources/DeviceLinkProtocol/PropertyHarness.swift` + the `ProtocolCheck` runner
pattern) instead of SwiftCheck/XCTest. This still meets the **PBT-09 intent** — custom generators,
shrinking-lite, and seeded reproducibility. On a machine with Xcode you would swap to
**SwiftCheck + XCTest** with no design change. Kotlin/JVM uses **Kotest property testing** normally.

## Notes
- `androidx.security:security-crypto` (EncryptedSharedPreferences) is the one runtime dependency
  specific to U2; everything else (keygen, hashing, JSON) uses platform/standard libraries.
- The full **X.509 self-signed certificate** wrapping the P-256 key (for the mTLS handshake) is
  produced/consumed at the U3 boundary; U2 owns the keypair + fingerprint + pin.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
