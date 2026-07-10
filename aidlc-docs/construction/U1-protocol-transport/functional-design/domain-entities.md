# Domain Entities — U1 Protocol / Transport core

Technology-agnostic domain model for the wire contract. Implemented later in Swift (`protocol/swift`)
and Kotlin (`protocol/kotlin`); this file defines the *concepts*, not the code.

---

## E1. Message (control envelope)
The unit of all control traffic.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID (string) | Unique per message (Q3). |
| `type` | MessageType (string enum) | `feature.action`, e.g. `pair.request`. Drives schema lookup. |
| `protocolVersion` | integer | Starts at `1` (Q2). |
| `replyTo` | UUID (string), optional | Correlates a response to a prior message's `id` (Q3). |
| `payload` | object (per-type schema) | Validated against `MessageType`'s schema. May contain base64 blobs ≤ 32 KiB (Q6). |

**Serialized form**: UTF-8 JSON, preceded by a **4-byte unsigned big-endian length prefix** (Q1).
Max serialized control message = **1 MiB**.

## E2. MessageType (registry enum)
Namespaced string enum, single source of truth for valid control types.

Initial v1 set (extended as feature units land):
`pair.request`, `pair.response`, `link.hello`, `link.heartbeat`,
`notif.posted`, `sms.received`, `sms.thread`, `file.offer`, `file.accept`, `file.progress`,
`clip.update`, `screen.start`, `screen.stop`, `call.incoming`, `call.action`, `call.history`.

Each `MessageType` maps to a **Schema** (E5). Unknown types fail validation (→ drop, Q5).

## E3. FrameHeader (binary framing)
Header for bulk/streaming data (files, screen frames). Fixed 13-byte big-endian layout (Q4).

| Field | Type | Bytes | Notes |
|-------|------|:-----:|-------|
| `streamId` | u32 | 4 | Identifies a logical stream multiplexed on the session. |
| `sequence` | u32 | 4 | Monotonic per stream; enforces ordering. |
| `length` | u32 | 4 | Payload byte count following the header. |
| `flags` | u8 | 1 | Bit flags; `END_OF_STREAM = 0x01` (others reserved). |

**Default chunk size**: 64 KiB payload per frame (Q4).

## E4. Frame
`{ header: FrameHeader, payload: bytes }` — one framed chunk on a stream.

## E5. Schema
Per-`MessageType` description of the expected `payload` shape: required fields, types, and size
caps. Used by validation (E6). (Concrete representation — e.g. a validator function vs. a data
schema — is decided at Code Generation; functionally it's "the rules for a valid payload of type T".)

## E6. ValidationResult
Outcome of validating an inbound Message or Frame.
- `valid: bool`
- `reason: ValidationFailure?` — one of: `MALFORMED_LENGTH`, `MALFORMED_JSON`, `OVERSIZE`,
  `UNKNOWN_TYPE`, `SCHEMA_MISMATCH`, `BAD_FRAME_HEADER`, `VERSION_MISMATCH`.

Failure → drop + log security event (Q5 / SECURITY-15). `VERSION_MISMATCH` is special: it surfaces
to the connection layer (U3) to reject the link (Q2).

## E7. ProtocolError (typed)
Enumerated decode/validation errors mirroring `ValidationFailure`, raised by codecs so callers can
fail-closed without inspecting strings. Never carries payload contents (CC-PRIV).

---

## Relationships
```
MessageType ──maps to──▶ Schema
Message ──has type──▶ MessageType ──validated by──▶ ValidationResult
Frame ──has──▶ FrameHeader
Codec(encode/decode) ──produces/consumes──▶ Message | Frame ──may raise──▶ ProtocolError
```

## Out of scope for U1 (owned elsewhere)
- `ConnectionState`, mTLS, streams lifecycle → **U3**.
- Per-feature payload *semantics* (what an `sms.received` body means) → each feature unit's
  Functional Design. U1 only fixes the **envelope, framing, registry, validation, and codecs**.
