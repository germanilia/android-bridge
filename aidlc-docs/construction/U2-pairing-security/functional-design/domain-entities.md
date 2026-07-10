# Domain Entities — U2 Pairing & Security

Technology-agnostic domain model for first-time trust establishment and encrypted persistence.
Implemented per platform: Kotlin (`android/app/.../core/Pairing.kt`, `SecureStore`) and Swift
(`mac/` — Keychain-backed, not yet written). Stories: US-1.1, US-1.2, US-1.3. Depends on U1.

---

## E1. DeviceIdentity
This device's stable, self-generated identity. The private key never leaves `SecureStore`.

| Field | Type | Notes |
|-------|------|-------|
| `deviceId` | UUID (string) | Stable per install. |
| `deviceName` | string | Human-readable (e.g. "Ilia's Mac"). |
| `publicKeyB64` | string | Base64 of the EC P-256 public key (DER/X.509 SubjectPublicKeyInfo). Only public material travels. |

Mirrors the Kotlin `DeviceIdentity` record. The matching private key is stored separately under
`identity.private` in `SecureStore` (E6) and is **never** serialized into a QR or message.

## E2. QrPayload
The pairing material encoded into the QR shown on one device and scanned/entered on the other.

| Field | Type | Notes |
|-------|------|-------|
| `deviceId` | UUID | The advertiser's id. |
| `deviceName` | string | Display name. |
| `publicKeyB64` | string | Advertiser's public key. |
| `fingerprint` | string | SHA-256 of `publicKeyB64` bytes, `:`-joined hex. Self-checking (BR-2). |
| `host` | string | LAN connection hint. |
| `port` | int | LAN connection hint. |

Serialized as compact JSON (round-trip is a PBT target — PBT-02).

## E3. PairedDevice
A peer pinned at pairing time (trust-on-first-use). Persisted in the trusted-device list.

| Field | Type | Notes |
|-------|------|-------|
| `deviceId` | UUID | Peer id. |
| `deviceName` | string | Peer display name. |
| `publicKeyB64` | string | Pinned public key. |
| `fingerprint` | string | Pinned fingerprint — the trust anchor checked at connect time (U3). |
| `host` / `port` | string / int | Last-known endpoint hint. |

## E4. Fingerprint
Derived value: `SHA-256(decodeBase64(publicKeyB64))` rendered as `:`-joined lowercase hex.
Deterministic (E1 → same fingerprint always — PBT-03 invariant). Used to pin and to match a peer.

## E5. PairResult
Outcome of consuming a QR: `pinned: PairedDevice` on success, or a typed failure
(`FINGERPRINT_MISMATCH`, `MALFORMED_QR`). Failure raises a security event (BR-2 / SECURITY-03).

## E6. SecureStore (trust store)
Encrypted key→value persistence for trust material. Keys used by U2:
`identity` (DeviceIdentity JSON), `identity.private` (private key), `paired.devices` (PairedDevice list).
Backed by **Keychain** (Mac) / **Android Keystore-derived key + EncryptedSharedPreferences**
(SECURITY-01/-12). An in-memory implementation backs pure tests.

---

## Relationships
```
DeviceIdentity ──fingerprintOf──▶ Fingerprint ──embedded in──▶ QrPayload
QrPayload ──consume + verify──▶ PairedDevice ──pinned in──▶ SecureStore[paired.devices]
DeviceIdentity.private ──stored in──▶ SecureStore[identity.private]  (never travels)
```

## Out of scope for U2 (owned elsewhere)
- mTLS handshake, cert chain validation at connect time → **U3** (consumes the pinned fingerprint).
- QR *image* rendering / camera scan UI → app shells (**U11/U12**).
- Per-feature permission grants → **U10**.
