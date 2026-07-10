# Business Rules — U6 File Transfer

Decision rules, validation logic, and constraints for file transfer. IDs (BR-x) are referenced by
NFR Design and Code Generation. Framing/codec rules are inherited from U1; U6 rules govern the
transfer protocol on top of them.

---

## Handshake & streaming
- **BR-1**: Bytes are sent **only after** a `file.accept{accept:true}` for the matching `transferId`
  (offer/accept handshake). No bytes precede acceptance.
- **BR-2**: Bulk bytes are chunked at the U1 default **64 KiB** per frame; the final frame carries
  `END_OF_STREAM`. Empty files send a single zero-length `END_OF_STREAM` frame.
- **BR-3**: Each transfer uses a distinct `streamId`; bytes for different transfers never interleave
  on one stream.

## Reassembly & integrity (fail-closed)
- **BR-4**: A transfer is **complete** only when `END_OF_STREAM` is received, the reassembler reports
  `complete`, and the reassembled byte count equals the offered `size`. Otherwise → `failed`.
- **BR-5**: Received `name` is **sanitized** (strip path separators, leading dots) before composing
  the destination path; never trust the peer's filename as a path.
- **BR-6**: A wrong-stream frame, a `sequence` gap, or a duplicate **faults** the transfer — drop the
  stream, log a security event, emit `status: failed`, and write **no** partial file (mirrors the U1
  `StreamReassembler` ordering invariant; SECURITY-15 fail-closed).

## Progress & destination
- **BR-7**: `file.progress.bytesSent` is monotonic non-decreasing and never exceeds `total`; every
  transfer terminates with exactly one of `status: complete` or `status: failed` (FR-5.2).
- **BR-8**: Received files are written under the **configured Destination** (FR-5.3, US-5.3),
  default platform Downloads; on name collision, de-duplicate rather than overwrite.
- **BR-9**: Writes are atomic where the platform allows (temp + rename) so a failed transfer leaves
  no half-written file at the destination.

## Transport & privacy
- **BR-10**: Bulk transfer always rides the **LAN** mTLS link, never Bluetooth (FR-5.4); inbound
  control/frames are validated + safely deserialized before use (CC-VALID, Inherited U1/U3).
- **BR-11**: File **names and contents** never appear in logs; logs may carry `transferId`,
  `streamId`, sizes, sequence numbers, and failure reasons only (CC-PRIV / SECURITY-03).

## Property-based testing (PBT partial)
- **BR-12 (PBT-03)**: `reassemble(chunk(data)) == data` for arbitrary byte arrays and sizes.
- **BR-13 (PBT-03)**: chunking invariants — total length preserved, exactly one final
  `END_OF_STREAM`, contiguous `0..n-1` sequences.

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-5.1 (Mac→phone drag-and-drop) | BR-1..BR-10 |
| US-5.2 (phone→Mac) | BR-1..BR-10 (roles swapped) |
| US-5.3 (configurable destination) | BR-5, BR-8, BR-9 |
| FR-5.2 (progress + result) | BR-7 |
| FR-5.4 (LAN not Bluetooth) | BR-10 |
| CC-VALID / SECURITY-15 (fail-closed) | BR-4, BR-6, BR-10 |
| CC-PRIV / SECURITY-03 (no PII in logs) | BR-11 |
