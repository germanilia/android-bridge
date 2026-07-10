# Domain Entities — U6 File Transfer

Technology-agnostic domain model for bidirectional file transfer over the device link. Bulk bytes
ride the U1 **binary frame** stream (`FrameHeader`/`Frame` + `StreamChunker`/`StreamReassembler`);
control (offer/accept/progress) rides U1 **control messages**. Implemented later in Swift
(`mac/Plugins/FileTransfer`) and Kotlin (`android/.../feature` + plugin). Concepts only, not code.

---

## E1. FileMeta
Descriptor of a file being offered. Travels inside the `file.offer` payload.

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | File name only (no path). Sanitized before use as a destination filename. |
| `size` | integer (bytes) | Declared total; drives progress + reassembly completion check. |
| `mime` | string, optional | Best-effort content type; advisory. |

## E2. TransferId
UUID identifying one transfer end-to-end. Correlates `file.offer` → `file.accept` → `file.progress`
and the binary `streamId` carrying the bytes.

## E3. FileOffer — `file.offer`
Control message proposing a transfer. Payload: `{ transferId, name, size, mime?, streamId }`.
The `streamId` names the U1 frame stream the bytes will use once accepted.

## E4. FileAccept — `file.accept`
Receiver's response. Payload: `{ transferId, accept: bool }`. Bytes are **only** sent after an
`accept: true` (offer/accept handshake — BR-1). `accept: false` ends the transfer cleanly.

## E5. TransferProgress — `file.progress`
Status updates surfaced to both UIs (FR-5.2). Payload: `{ transferId, bytesSent, total, status }`
where `status ∈ {sending, complete, failed}`. `bytesSent` is monotonic non-decreasing (BR-7).

## E6. Destination
Per-platform configured output folder (FR-5.3, US-5.3). `{ path }`. Persisted via Settings (U10);
default = platform Downloads. Received files are written under this path with a sanitized `name`.

## E7. FrameHeader / Frame *(reused from U1)*
The bulk payload is carried by U1's `Frame { header: FrameHeader, payload: bytes }` with
`streamId`, monotonic `sequence`, `length`, and `END_OF_STREAM` flag — 64 KiB default chunks.
U6 adds **no** new framing; it consumes the U1 contract.

## E8. TransferState (internal)
Per-transfer bookkeeping on each side: `{ transferId, role: send|receive, bytesSent, total,
streamId, faulted: bool }`. Drives progress emission and fail-closed abort.

---

## Relationships
```
FileOffer ──transferId──▶ FileAccept ──gates──▶ Frame[] (on streamId) ──reassemble──▶ Destination
TransferState ──emits──▶ TransferProgress
```

## Out of scope for U6 (owned elsewhere)
- Frame codec, ordering invariant, fail-closed stream abort → **U1** (`StreamReassembler`).
- mTLS session + `openStream` multiplexing → **U3**.
- Drag-and-drop UI, progress UI, destination picker → **U11 / U12** shells; persistence → **U10**.
