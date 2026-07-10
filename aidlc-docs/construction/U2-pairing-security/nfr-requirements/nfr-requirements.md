# NFR Requirements — U2 Pairing & Security

U2 is the **trust foundation**: per-device identity, QR pairing, and encrypted-at-rest persistence.
It has crypto + storage but no live network (that's U3). Security is the headline NFR here.

---

## NFR-U2.1 Security (Baseline ON — applicable rules) *(headline)*
| Rule | Applies | How |
|------|---------|-----|
| SECURITY-01 (encryption at rest) | ✅ Owned | All trust material in Keychain / Keystore+EncryptedSharedPreferences; no plaintext on disk (BR-5). |
| SECURITY-12 (credential management) | ✅ Owned | Private key generated on-device, kept in secure store, never serialized/logged; no hardcoded secrets (BR-4). |
| SECURITY-06/-08 (least privilege / access control) | ✅ Owned | Trust-on-first-use pins exactly one key per peer; deny-by-default — only pinned peers are honored by U3 (BR-9). |
| SECURITY-15 (fail-closed) | ✅ Owned | Fingerprint mismatch / malformed QR → reject + security event, never a partial pin (BR-2). |
| SECURITY-03 (no-PII logging) | ✅ Owned | Pairing/security logs carry only `deviceId` + event (BR-10). |
| SECURITY-05/-13 (input validation / safe deser) | ◻ Inherited | QR JSON parsed via the same safe-deser discipline as U1; U2 adds the fingerprint check. |
| SECURITY-10 (supply chain) | ⏳ Deferred | Dependency pinning + scan + SBOM handled at Build & Test. |
| SECURITY-02/-04/-07/-09/-11/-14 | N/A | No cloud/web tier, load balancer, HTTP endpoint, rate-limit surface, or cloud alerting in a local pairing module. |

## NFR-U2.2 Reliability / correctness
- Pairing is **deterministic and fail-closed**: a tampered or malformed QR never yields a pinned
  peer (BR-2). `pinPeer`/`unpair` leave the trusted list in a consistent state (BR-6/-7).
- Pure logic (fingerprint, QR codec, list ops) is total and side-effect-free → trivially testable.

## NFR-U2.3 Testability (PBT partial)
- QR round-trip (PBT-02) and fingerprint/trusted-list invariants (PBT-03) over domain generators
  (PBT-07), seeded + shrinking (PBT-08), framework per NFR (PBT-09).
- Example tests pin known-good/known-bad QR vectors (fingerprint match vs. mismatch).

## NFR-U2.4 Privacy & data locality
- No trust material leaves the device except the **public** key/fingerprint in the QR (NFR-1.1).
- At-rest encryption per platform secure store (NFR-1.3).

## NFR-U2.5 Maintainability / portability
- Pure pairing logic (keygen, fingerprint, QR, list) kept free of platform UI/IO so it is shared in
  shape across Swift/Kotlin and JVM-testable (NFR-6.2). Generic Android APIs only (NFR-6.1).

## Out of scope for U2 (asserted)
mTLS handshake, peer authentication at connect, auto-reconnect, throughput — **U3**. Availability /
scaling / DR — N/A (local, no service).
