# Business Logic Model — U2 Pairing & Security

Technology-agnostic flows for identity generation, QR pairing, trust pinning, and encrypted storage.
No transport/mTLS here (that's U3) — U2 establishes *who* to trust and persists it securely.
Orchestrated by `PairingService` (S2) over `PairingManager` (B2) + `SecureStore` (B5).

---

## L1. Generate identity  `generateIdentity(deviceName) -> DeviceIdentity`
1. Generate an **EC P-256** keypair (JDK `KeyPairGenerator("EC", 256)` / platform crypto).
2. Base64-encode public + private key material.
3. Persist `identity` (DeviceIdentity JSON) and `identity.private` to `SecureStore`.
4. Return the `DeviceIdentity` (public-only). The private key stays in `SecureStore` (BR-4).

## L2. Create pairing QR  `createPairingQr(identity, host, port) -> QrPayload`
1. Compute `fingerprint = fingerprintOf(identity.publicKeyB64)` (L5).
2. Assemble `QrPayload{deviceId, deviceName, publicKeyB64, fingerprint, host, port}`.
3. Serialize to compact JSON; the shell renders it as a QR image (US-1.1).

## L3. Consume pairing QR  `consumePairingQr(qr) -> PairedDevice`  *(trust boundary — fail-closed)*
1. Parse the QR JSON → `QrPayload`; parse failure → `MALFORMED_QR` (drop + security event).
2. Recompute `expected = fingerprintOf(payload.publicKeyB64)`.
3. If `expected != payload.fingerprint` → **reject**, log `pair_fingerprint_mismatch`, raise
   `FINGERPRINT_MISMATCH` (BR-2 / SECURITY-15). This guards against a tampered QR.
4. Build `PairedDevice` from the verified payload and `pinPeer` it (L4) — trust-on-first-use (BR-1).
5. Return the pinned peer.

## L4. Pin / list / unpair (trusted-device management)
- `pinPeer(peer)`: replace any existing entry with the same `deviceId`, append, persist
  `paired.devices`; log `peer_pinned` (US-1.1).
- `listPaired() -> [PairedDevice]`: read + deserialize `paired.devices` (empty if none) (US-1.3).
- `unpair(deviceId)`: remove the entry, persist, log `peer_unpaired`. The peer can no longer
  connect until re-paired (BR-5 / US-1.3 / FR-1.4).
- `isPinned(fingerprint) -> Bool`: U3 calls this at connect time to enforce CC-SEC.

## L5. Fingerprint  `fingerprintOf(publicKeyB64) -> Fingerprint`
`SHA-256(decodeBase64(publicKeyB64))` → `:`-joined lowercase hex. Pure + deterministic.

---

## Data flow (one pairing)
```
Mac: generateIdentity → createPairingQr ──QR image──▶ shown on screen
Android: scan QR ──▶ consumePairingQr ──verify fingerprint──▶ pinPeer ──▶ SecureStore[paired.devices]
(symmetric: both sides pin the other; U3 then connects over mTLS against the pinned fingerprint)
```

## Testable Properties (PBT-01)
| Property | Category | Statement |
|----------|----------|-----------|
| QR round-trip (PBT-02) | Round-trip | `decode(encode(qr)) == qr` for all generated `QrPayload`s. |
| Fingerprint determinism (PBT-03) | Invariant | `fingerprintOf(k)` is stable across calls; equal keys → equal fingerprints. |
| Trusted-list invariant (PBT-03) | Invariant | After `pinPeer(p)`, `listPaired()` contains `p` exactly once by `deviceId`; after `unpair(p.id)` it is absent. |

These are **pure / JVM-testable** (no network, no device). Crypto keypair generation is deterministic
in shape (always a valid P-256 keypair) — exercised by example tests, not PBT. Kotlin uses Kotest
property testing; the Swift port uses the seeded `PropertyHarness` (no Xcode on this machine).
