# Business Logic Model — U1 Protocol / Transport core

Technology-agnostic flows for encoding, decoding, framing, and validation. No transport/mTLS here
(that's U3) — U1 turns domain objects ⇄ bytes and guards the trust boundary on inbound bytes.

---

## L1. Encode control message  `encode(message) -> bytes`
1. Assert `message.protocolVersion == 1`; assert required envelope fields present.
2. Serialize envelope to **UTF-8 JSON** (stable key handling so round-trip is exact — PBT-02).
3. Assert serialized length ≤ **1 MiB**; else raise `ProtocolError(OVERSIZE)`.
4. Prepend **4-byte unsigned big-endian length** = JSON byte count.
5. Return `lengthPrefix ++ jsonBytes`.

## L2. Decode control message  `decode(bytes) -> Message`  *(trust boundary — fail-closed)*
1. Read 4-byte length prefix; if fewer bytes available → `MALFORMED_LENGTH`.
2. If declared length > **1 MiB** → `OVERSIZE` (reject before allocating/parsing).
3. Parse exactly `length` bytes as UTF-8 JSON; parse failure → `MALFORMED_JSON`.
4. Check `protocolVersion`; mismatch → `VERSION_MISMATCH` (surfaces to U3 to reject link).
5. Look up `type` in the Message Type Registry; not found → `UNKNOWN_TYPE`.
6. Validate `payload` against the type's **Schema** (fields, types, size caps); fail → `SCHEMA_MISMATCH`.
7. On any failure: **return/raise the typed error → caller drops + logs a security event, does not crash** (Q5).
8. On success: return the typed `Message`.

## L3. Encode frame  `encodeFrame(header, payload) -> bytes`
1. Assert `payload.length == header.length` and `header.length ≤ 64 KiB` (default chunk).
2. Write big-endian header: `streamId(u32) · sequence(u32) · length(u32) · flags(u8)`.
3. Return `headerBytes ++ payload`.

## L4. Decode frame  `decodeFrame(bytes) -> Frame`  *(trust boundary)*
1. Require ≥ 13 header bytes; else `BAD_FRAME_HEADER`.
2. Parse header; if remaining bytes < `length` → `BAD_FRAME_HEADER` (incomplete).
3. Slice `length` payload bytes; return `Frame(header, payload)`.
4. Malformed → drop + log (Q5); ordering/reassembly is the consumer's concern (U3/feature units),
   but `sequence` + `END_OF_STREAM` give them what they need.

## L5. Stream reassembly contract (consumed by U3 + bulk features)
- Frames on the same `streamId` are delivered in `sequence` order; a gap or duplicate is a fault →
  the consumer aborts that stream (fail-closed). U1 *defines* the invariant; U3 enforces transport.
- `END_OF_STREAM` flag marks the final frame; no payload bytes are expected after it on that stream.

## L6. Inline-vs-stream routing for binary (Q6)
- Producing a control message with binary data: if blob ≤ **32 KiB**, base64-encode it inline in
  `payload`; otherwise open a frame stream and reference its `streamId` in the control message.
- This keeps `decode`/`encode` purely JSON for control and isolates bulk to frames.

---

## Data flow (one round trip)
```
domain Message ──L1 encode──▶ [4B len | JSON] ──(U3 mTLS send)──▶ peer
peer bytes ──(U3 mTLS recv)──▶ L2 decode ──valid?──▶ Message ──▶ MessageRouter (U3) ──▶ plugin
                                        └──invalid──▶ drop + LinkLogger.securityEvent
```

## PBT hooks (realized at Code Generation, both languages)
- **PBT-02**: for all valid `m`, `decode(encode(m)) == m` (envelope round-trip).
- **PBT-03**: for all valid `(header, payload)`, `decodeFrame(encodeFrame(header, payload)) == (header, payload)`;
  and length-prefix framing is self-delimiting (concatenated encodes split back to the same messages).
- **PBT-07**: domain generators produce arbitrary valid Messages/Frames across all registry types.
