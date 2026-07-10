# NFR Design — U2 Pairing & Security

How U2's NFRs are realized concretely. Cites SECURITY-xx rule IDs; N/A rules marked with rationale.
Infrastructure Design is **skipped** for all units (local P2P, no cloud).

---

## Security patterns

### Encryption at rest (SECURITY-01 / SECURITY-12) — Owned
- **Android**: `AndroidSecureStore` wraps `EncryptedSharedPreferences` with a Keystore-derived
  `MasterKey` (`AES256_GCM`); keys/values encrypted (`AES256_SIV` / `AES256_GCM`). The EC private
  key, identity, and trusted list live only here.
- **Mac**: `SecureStore` backed by **Keychain** items (when-unlocked accessibility), Secure
  Enclave-eligible key storage where available.
- A common `SecureStore` interface + `InMemorySecureStore` lets pure logic be tested without touching
  the OS keystore.

### Credential management (SECURITY-12) — Owned
- Per-device EC P-256 keypair generated on-device; **private key never serialized** into QR, message,
  or log (BR-4). No hardcoded secrets anywhere (no accounts, no shared key).

### Trust model / least privilege (SECURITY-06 / SECURITY-08) — Owned
- **Trust-on-first-use pinning**: exactly one public key per peer is pinned. Deny-by-default — U3
  honors *only* pinned fingerprints (BR-9). Unpair revokes (BR-7).

### Fail-closed validation (SECURITY-15) — Owned
- `consumePairingQr` recomputes and compares the fingerprint before pinning; any mismatch/parse
  failure aborts the pairing and emits a security event — never a partial or unverified pin (BR-2).

### No-PII logging (SECURITY-03) — Owned
- `LinkLogger` records only event name + `deviceId`; its forbidden-key filter drops any body/key/
  token/name field passed by mistake (BR-10).

### Input validation / safe deserialization (SECURITY-05 / SECURITY-13) — Inherited
- QR JSON is parsed with the same strict, allowlisted deserialization discipline as U1; U2 layers the
  fingerprint integrity check on top.

### Supply chain (SECURITY-10) — Deferred
- Dependency pinning (Gradle lockfile / SPM `Package.resolved`), vulnerability scan, and SBOM are
  realized at **Build & Test**.

### N/A (rationale)
SECURITY-02 (no load balancer/CDN), SECURITY-04 (no HTML endpoint), SECURITY-07 (no cloud VPC),
SECURITY-09 beyond generic-error (no server/admin surface), SECURITY-11 rate-limiting (no public
endpoint), SECURITY-14 cloud alerting (local security events go to `LinkLogger`, no cloud).

## Performance / reliability patterns
- Pairing is a one-shot, human-paced flow — no latency target. Keygen happens once per install.
- Pure logic is total and deterministic (NFR-U2.2); failure modes are typed, not exceptions across
  the boundary.

## Testability pattern (PBT)
- QR round-trip (PBT-02) + fingerprint/list invariants (PBT-03) with domain generators (PBT-07),
  shrinking + seed logging (PBT-08).
- **Environment deviation**: no Xcode → Swift uses the seeded `PropertyHarness` (not SwiftCheck/
  XCTest); meets PBT-09 intent (generators + shrinking-lite + seeded reproducibility). Kotlin uses
  Kotest property testing. On a machine with Xcode, swap to SwiftCheck + XCTest unchanged.

## Logical components (no infrastructure)
`PairingManager` (B2, pure trust logic) · `SecureStore` (B5, encrypted persistence) ·
`PairingService` (S2, orchestration) · `LinkLogger` (B7, redacting logger). All in-process; no
queues, caches, or external services.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
