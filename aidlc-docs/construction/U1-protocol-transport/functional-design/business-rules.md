# Business Rules — U1 Protocol / Transport core

Decision rules, validation logic, and constraints for the wire contract. IDs (BR-x) are referenced
by NFR Design and Code Generation.

---

## Format & sizing
- **BR-1**: Control messages are UTF-8 JSON with a **4-byte unsigned big-endian length prefix** (Q1).
- **BR-2**: Max serialized control message = **1 MiB**. Encode raises `OVERSIZE`; decode rejects an
  oversize declared length *before* allocating or parsing (anti-DoS) (Q1 / SECURITY-15).
- **BR-3**: Binary frame header is fixed **13 bytes**, big-endian: `streamId(u32)·sequence(u32)·length(u32)·flags(u8)` (Q4).
- **BR-4**: Default frame chunk payload = **64 KiB**; `length` must equal the actual payload size.
- **BR-5**: Binary blobs **≤ 32 KiB** may be base64-inline in a control payload; larger binary **must**
  use a frame stream (Q6).

## Versioning
- **BR-6**: `protocolVersion` is a single integer; v1 = `1` (Q2).
- **BR-7**: On decode, a `protocolVersion` ≠ local version → `VERSION_MISMATCH`, surfaced to U3 which
  **rejects the connection** (no negotiation in v1) (Q2).

## Identity & correlation
- **BR-8**: Every Message carries a **UUID `id`** (Q3).
- **BR-9**: A response *may* set `replyTo = <request id>`; correlation is optional — absence means
  fire-and-forget. U1 does not enforce that a `replyTo` matches a known id (that's caller policy).

## Type registry & validation (CC-VALID, trust boundary)
- **BR-10**: `type` must exist in the Message Type Registry; unknown → `UNKNOWN_TYPE` (Q5).
- **BR-11**: `payload` must conform to the registered Schema (required fields, value types, per-field
  size caps); violation → `SCHEMA_MISMATCH`.
- **BR-12**: Decoding **always validates before** handing a Message to any consumer (SECURITY-05/-13).
- **BR-13**: Validation is **total** — every inbound byte sequence yields either a valid typed Message/
  Frame or a typed failure; **no unchecked/partial objects escape the codec**.

## Fail-closed behavior (SECURITY-15)
- **BR-14**: Any control decode/validation failure → **drop the message, log a security event, keep the
  connection open** (Q5). The link is not torn down for a single bad control message.
- **BR-15**: Exception: `VERSION_MISMATCH` → connection rejected (BR-7).
- **BR-16**: Any frame decode failure → **abort that `streamId`** (drop the stream, log), keep the
  connection + other streams alive (Q5).
- **BR-17**: A frame `sequence` gap or duplicate on a stream → the stream is faulted and aborted
  (ordering invariant, L5).

## Privacy (CC-PRIV / SECURITY-03)
- **BR-18**: Codecs and logged security events **never** include payload contents, phone numbers,
  contacts, message bodies, or tokens. Logs may carry `type`, `id`, `streamId`, sizes, and failure reason.

## Property-based testing (PBT partial)
- **BR-19 (PBT-02)**: `decode(encode(m)) == m` for all valid Messages.
- **BR-20 (PBT-03)**: `decodeFrame(encodeFrame(h, p)) == (h, p)`; length-prefix framing is
  self-delimiting (concatenation splits back exactly).
- **BR-21 (PBT-07/-08)**: domain generators cover all registry types; CI runs are seeded and shrink on
  failure; framework chosen at NFR Requirements (PBT-09).

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-10.2 (documented, separable protocol + round-trip PBT) | BR-1..BR-21; deliverable = `PROTOCOL.md` + Swift/Kotlin codecs + PBT |
| CC-VALID (validate + safe-deserialize inbound) | BR-10..BR-14, BR-16, BR-17 |
| CC-PRIV (no PII in logs) | BR-18 |
| SECURITY-05/-13 (input validation, safe deserialization) | BR-10..BR-13 |
| SECURITY-15 (fail-closed) | BR-2, BR-14..BR-17 |
