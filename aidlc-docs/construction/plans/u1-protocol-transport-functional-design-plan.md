# Functional Design Plan — U1 Protocol / Transport core

Role: Software architect. This plan defines **how** we'll produce the detailed, technology-agnostic
functional design for **U1 — Protocol/Transport core** (the wire contract every other unit depends on).

**Unit scope** (from `unit-of-work.md`): Message Envelope, Binary Frame, Message Type Registry,
length-prefixed JSON control codec, binary frame codec. **Story**: US-10.2. **Primary PBT-02 surface.**
**Deliverable per Q3**: `protocol/PROTOCOL.md` spec + Swift + Kotlin codecs + round-trip PBT in both.

**Action**: Answer **Q1–Q6** (`[Answer]:`), then approve. Artifact generation starts only after approval.

> Note: This is **design only** (entities, rules, formats) — no code yet. Code comes at U1 Code Generation.

---

## Plan checkboxes (executed 2026-06-30)
- [x] Generate `aidlc-docs/construction/U1-protocol-transport/functional-design/domain-entities.md` — Message, MessageType, FrameHeader, Schema, ValidationResult, etc.
- [x] Generate `.../business-logic-model.md` — encode/decode flows, framing, validation pipeline
- [x] Generate `.../business-rules.md` — size limits, versioning, fail-closed rules, PBT properties
- [x] (No frontend in U1 — `frontend-components.md` N/A)
- [x] Validate against US-10.2 + CC-VALID, confirm PBT-02/-03 properties are stated

---

## Proposed design (default recommendation)

- **Envelope**: `{ id, type, protocolVersion, payload }`, serialized as **UTF-8 JSON**, sent with a
  **4-byte unsigned big-endian length prefix** (max control message **1 MiB**).
- **protocolVersion**: a single **integer** (start at `1`); on mismatch → **reject the connection**
  (no negotiation in v1).
- **id**: a **UUID string** per message; enables optional request/response correlation (`replyTo`).
- **type**: a **string enum** namespaced `feature.action` (e.g. `pair.request`, `sms.received`); the
  Type Registry maps `type → payload schema`.
- **Binary Frame** (bulk/streaming): fixed header **streamId (u32) · sequence (u32) · length (u32) ·
  flags (u8)** big-endian, then `length` payload bytes; `flags` carries **END_OF_STREAM**. Default
  **chunk size 64 KiB**.
- **Validation (CC-VALID, fail-closed)**: decode validates magic/length/JSON well-formedness, known
  `type`, schema conformance, and size caps; **any failure → drop + log a security event, never crash**.
- **PBT**: `decode(encode(m)) == m` for all valid messages (PBT-02); frame round-trip + ordering
  invariants (PBT-03).

---

## Questions

### Q1 — Control-message length prefix & size cap
- **A) 4-byte unsigned big-endian length prefix, max control message 1 MiB** (recommended) — simple, ample for JSON control; bulk goes through frames anyway.
- B) 2-byte prefix (max 64 KiB) — tighter, but risks truncating large MMS/contact payloads.
- C) Varint length prefix — compact, slightly more code.
- X) Other (describe)

[Answer]:

### Q2 — protocolVersion type & mismatch behavior
- **A) Single integer, reject connection on mismatch** (recommended) — simplest; both apps ship together in v1.
- B) Semver string with min-compatible negotiation — future-proof, more logic now.
- C) Integer with "accept if peer ≥ mine" leniency.
- X) Other (describe)

[Answer]:

### Q3 — Message id & request/response correlation
- **A) UUID string id on every message + optional `replyTo` field for correlation** (recommended) — supports request/response (e.g. file.offer→accept) without forcing it.
- B) Monotonic per-connection counter id (smaller, but resets on reconnect).
- C) No id in v1 (fire-and-forget only) — simplest, but blocks clean acks/correlation.
- X) Other (describe)

[Answer]:

### Q4 — Binary frame header layout & default chunk size
- **A) streamId(u32) · sequence(u32) · length(u32) · flags(u8), big-endian; 64 KiB default chunk** (recommended) — 13-byte header, headroom for many concurrent streams + large files.
- B) Smaller header (streamId u16, sequence u32, length u16) with 16 KiB chunks — leaner, lower ceilings.
- C) Leave exact sizes to Code Generation; fix only field set now.
- X) Other (describe)

[Answer]:

### Q5 — Unknown / malformed message handling (fail-closed detail)
- **A) Drop + log security event; keep the connection open** (recommended) — resilient to a single bad/unknown message; matches SECURITY-15 + graceful behavior.
- B) Drop + close the connection on any malformed frame — stricter, but a single glitch kills the link.
- C) Unknown `type` → drop; malformed envelope/frame → close — hybrid.
- X) Other (describe)

[Answer]:

### Q6 — Binary payloads inside JSON control messages (e.g. small icons, MMS thumbnails)
- **A) Base64-encode small blobs inline; anything large goes over a binary frame stream** (recommended) — keeps control messages pure JSON; a size threshold (e.g. 32 KiB) routes big data to frames.
- B) Always use a frame stream for any binary, never inline — cleanest separation, more streams for tiny icons.
- C) Decide per message type later in each feature's Functional Design.
- X) Other (describe)

[Answer]:

---

## Recommendation in one line
Q1=A · Q2=A · Q3=A · Q4=A · Q5=A · Q6=A  (reply **"go"** to accept all).

---

## Answers (recorded 2026-06-30)
- **Q1 = A** — 4-byte unsigned big-endian length prefix; max control message 1 MiB.
- **Q2 = A** — protocolVersion = single integer (start at 1); reject connection on mismatch.
- **Q3 = A** — UUID string id per message + optional `replyTo` for correlation.
- **Q4 = A** — frame header streamId(u32)·sequence(u32)·length(u32)·flags(u8) big-endian; 64 KiB default chunk.
- **Q5 = A** — malformed/unknown → drop + log security event, keep connection open (fail-closed).
- **Q6 = A** — base64 small blobs inline (≤32 KiB threshold); larger binary over a frame stream.

(User response: "go" — accepted all recommendations. No ambiguities.)
