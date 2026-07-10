# Device-Link Protocol (v1)

Canonical, language-neutral wire contract for **android_bridge**. Implemented identically in
`protocol/kotlin` (Kotlin/JVM) and `protocol/swift` (SwiftPM). This document is the single source of
truth; both implementations and their round-trip property tests must conform to it.

> Decisions: U1 Functional Design Q1–Q6 (see `aidlc-docs/construction/U1-protocol-transport/`).

---

## 1. Transport framing model

A single mutual-TLS session (owned by U3, not U1) carries two interleaved kinds of bytes:

1. **Control messages** — length-prefixed JSON (this doc §2–§4).
2. **Binary frames** — fixed-header chunks for bulk/streaming data (this doc §5).

U1 defines only the *encoding/decoding/validation* of these two. It performs no I/O.

---

## 2. Control message envelope

A control message is a JSON object:

| Field | JSON type | Required | Notes |
|-------|-----------|:--------:|-------|
| `id` | string | yes | UUID (v4) unique per message. |
| `type` | string | yes | Namespaced `feature.action`; must be a registered type (§6). |
| `protocolVersion` | integer | no (default `1`) | Current version = **1**. Mismatch ⇒ reject connection. |
| `replyTo` | string | no | `id` of the message this responds to (correlation). |
| `payload` | object | no (default `{}`) | Per-type body (§6). May contain base64 blobs ≤ 32 KiB (§7). |

Defaults are omitted on the wire (compact encoding); decoders reconstruct them.

## 3. Control wire format

```
+-----------------------------+-------------------------------+
| length (uint32, big-endian) | JSON bytes (UTF-8, `length`)  |
+-----------------------------+-------------------------------+
```

- `length` = number of UTF-8 JSON bytes that follow.
- **Max control message = 1 048 576 bytes (1 MiB)** of JSON. Encoders reject larger; decoders reject
  a declared `length > 1 MiB` *before* allocating or parsing (anti-DoS).
- Multiple control messages on a stream are self-delimiting: concatenated encodings decode back to the
  same ordered sequence.

## 4. Decode pipeline (trust boundary — fail-closed)

1. Need ≥ 4 bytes for the prefix → else `MALFORMED_LENGTH`.
2. `length > 1 MiB` → `OVERSIZE` (before allocation).
3. Fewer than `length` bytes available → `MALFORMED_LENGTH`.
4. Parse `length` bytes as UTF-8 JSON → failure ⇒ `MALFORMED_JSON`.
5. `protocolVersion != 1` → `VERSION_MISMATCH` (surfaced to U3 to reject the link).
6. `type` not in the registry → `UNKNOWN_TYPE`.
7. `payload` violates the type's schema → `SCHEMA_MISMATCH`.
8. Otherwise → a valid typed `Message`.

Any failure returns a typed error; the caller drops the message + logs a security event and keeps the
connection open (except `VERSION_MISMATCH`, which rejects the link). No payload content is ever logged.

## 5. Binary frame

Fixed **13-byte big-endian** header, then `length` payload bytes:

| Field | Type | Bytes | Notes |
|-------|------|:-----:|-------|
| `streamId` | uint32 | 4 | Logical stream id, multiplexed on the session. |
| `sequence` | uint32 | 4 | Monotonic per stream; enforces ordering. |
| `length` | uint32 | 4 | Payload byte count. **Default chunk = 65 536 (64 KiB).** |
| `flags` | uint8 | 1 | Bit `0x01` = `END_OF_STREAM`; others reserved (0). |

Decode requires ≥ 13 header bytes and ≥ `length` payload bytes, else `BAD_FRAME_HEADER`.
Frame round-trip is exact: `decodeFrame(encodeFrame(h, p)) == (h, p)`.

## 6. Message type registry (v1)

`type` → payload schema. Initial v1 set (extended as feature units land):

| type | direction | payload (summary) |
|------|-----------|-------------------|
| `link.hello` | both | `{ deviceName, platform }` |
| `link.heartbeat` | both | `{}` |
| `pair.request` | both | `{ deviceName, certFingerprint }` |
| `pair.response` | both | `{ accepted, deviceName, certFingerprint }` |
| `notif.posted` | A→M | `{ pkg, title, text, postedAt }` |
| `sms.received` | A→M | `{ threadId, address, body, receivedAt }` |
| `sms.thread` | A→M | `{ threadId, messages[] }` |
| `file.offer` | both | `{ transferId, name, size, streamId }` |
| `file.accept` | both | `{ transferId, accepted }` |
| `file.progress` | both | `{ transferId, bytesSent }` |
| `clip.update` | both | `{ text }` |
| `screen.start` | both | `{ streamId, codec, maxBitrate }` |
| `screen.stop` | both | `{ streamId }` |
| `call.incoming` | A→M | `{ number, contactName?, photoB64? }` |
| `call.action` | M→A | `{ action, number? }` (answer/decline/dial) |
| `call.history` | A→M | `{ records[] }` |
| `meeting.start` | A→M | `{ meetingId, title?, startedAt }` |
| `meeting.stop` | A→M | `{ meetingId, stoppedAt }` |
| `meeting.audioChunk.offer` | A→M | `{ meetingId, sequence, startedAtMs, endedAtMs, checksum, name, data }` |
| `meeting.audioChunk.received` | M→A | `{ meetingId, sequence, checksum }` |
| `meeting.photo.offer` | A→M | `{ meetingId, photoId, capturedAtMs, checksum, name, data }` |
| `meeting.photo.received` | M→A | `{ meetingId, photoId, checksum }` |
| `meeting.processing.status` | M→A | `{ meetingId, state }` |
| `meeting.notes.ready` | M→A | `{ meetingId, path }` |

A=Android, M=Mac. Unknown types are rejected (§4 step 6).

Meeting capture v1 carries speech-optimized one-minute audio chunks and JPEG photos as base64 in control payloads. Each payload must remain under the 1 MiB control-message limit; larger future media must use binary frame streams referenced by `streamId`.

## 7. Binary inside JSON

Binary data carried in a control payload (small icons, MMS thumbnails) is **base64-encoded inline only
when ≤ 32 KiB** decoded. Anything larger MUST use a binary frame stream (§5), referenced by `streamId`.

## 8. Property-based tests (both languages)

- **PBT-02**: `decode(encode(m)) == m` for all valid messages.
- **PBT-03**: `decodeFrame(encodeFrame(h, p)) == (h, p)`; and length-prefix framing is self-delimiting
  (concatenated control encodings split back to the same sequence).
- **PBT-07**: domain generators produce valid messages across every registry type.

## 9. Constants

| Name | Value |
|------|-------|
| `PROTOCOL_VERSION` | 1 |
| `MAX_CONTROL_BYTES` | 1 048 576 (1 MiB) |
| `DEFAULT_CHUNK_BYTES` | 65 536 (64 KiB) |
| `INLINE_BLOB_MAX_BYTES` | 32 768 (32 KiB) |
| `FLAG_END_OF_STREAM` | 0x01 |
| `FRAME_HEADER_BYTES` | 13 |
