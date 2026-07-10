# Business Rules — U2 Pairing & Security

Decision rules, validation logic, and constraints for trust establishment and storage. IDs (BR-x)
are referenced by NFR Design and Code Generation. Stories US-1.1, US-1.2, US-1.3.

---

## Trust establishment (trust-on-first-use)
- **BR-1**: Pairing is **trust-on-first-use** — consuming a peer's QR pins its public key/fingerprint
  with no cloud or account involved (FR-1.2 / US-1.1).
- **BR-2**: On `consumePairingQr`, the embedded `fingerprint` **must equal** the recomputed
  `SHA-256(publicKey)`; mismatch → reject, raise `FINGERPRINT_MISMATCH`, log a security event. A
  malformed QR → `MALFORMED_QR`, same handling (fail-closed, SECURITY-15).
- **BR-3**: Each device generates its **own** EC P-256 keypair (FR-1.1). Pairing is mutual — both
  sides pin the other.

## Key material & secrecy
- **BR-4**: The **private key never leaves `SecureStore`** and never appears in a `QrPayload`,
  `Message`, or log. Only `publicKeyB64` + `fingerprint` travel (CC-PRIV / SECURITY-12).
- **BR-5**: All trust material (`identity`, `identity.private`, `paired.devices`) is persisted
  **encrypted at rest** — Keychain (Mac) / Keystore-derived key + EncryptedSharedPreferences
  (Android). No plaintext on disk (FR-1.5 / SECURITY-01/-12).

## Trusted-device management
- **BR-6**: `pinPeer` is idempotent by `deviceId` — re-pinning the same device replaces, does not
  duplicate, its entry.
- **BR-7**: `unpair(deviceId)` deletes the pinned trust; that peer **cannot reconnect** until
  re-paired (FR-1.4 / US-1.3). U3 enforces this at connect time via `isPinned`.
- **BR-8**: `listPaired()` surfaces each pinned device (name + status) to the UI (US-1.3).

## Boundary with U3 (connection)
- **BR-9**: U2 only *establishes and stores* trust. U3 *uses* the pinned fingerprint to authenticate
  the mTLS peer and **rejects unpinned peers** (CC-SEC). The pin is the single trust anchor shared
  across the two units.

## Privacy & logging (CC-PRIV / SECURITY-03)
- **BR-10**: Pairing logs/security events carry only `deviceId` and event name — never keys, QR
  contents, or names beyond an id. `LinkLogger` drops forbidden fields defensively.

## Property-based testing (PBT partial)
- **BR-11 (PBT-02)**: `decode(encode(qr)) == qr` for all valid `QrPayload`s.
- **BR-12 (PBT-03)**: `fingerprintOf` is deterministic; trusted-list pin/unpair invariants hold
  (see business-logic-model "Testable Properties").

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-1.1 (pair via QR) | BR-1..BR-3, BR-11 |
| US-1.2 (store secrets securely) | BR-4, BR-5 |
| US-1.3 (view/unpair) | BR-6..BR-8 |
| CC-SEC (only pinned peers) | BR-9 (enforced in U3) |
| CC-PRIV / SECURITY-03 | BR-4, BR-10 |
| SECURITY-01/-12 (at rest) | BR-5 |
| SECURITY-15 (fail-closed) | BR-2 |
