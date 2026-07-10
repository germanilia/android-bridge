# Business Logic Model — U6 File Transfer

Technology-agnostic flows for offering, accepting, streaming, reassembling, and reporting file
transfers. Bulk bytes use the U1 frame stream; control uses U1 control messages over the U3 mTLS
session. No transport/mTLS logic here (that's U3); no codec internals here (that's U1).

---

## L1. Offer a file  `offerFile(meta) -> transferId`  *(sender)*
1. Allocate `transferId` (UUID) and a `streamId` for the bulk channel.
2. Build `file.offer` payload `{ transferId, name, size, mime?, streamId }`; validate against Schema.
3. `ConnectionService.send(file.offer)`; record `TransferState{role: send, total: size}`.
4. Wait for `file.accept` before sending any bytes (BR-1).

## L2. Accept / decline  `onOffer(file.offer) -> file.accept`  *(receiver)*
1. Validate inbound `file.offer` (Inherited U1/U3 fail-closed); sanitize `name` (BR-5).
2. Surface the offer to the UI (U11/U12). On user accept → send `file.accept{accept:true}`; record
   `TransferState{role: receive, total: size, streamId}` and open the reassembler for `streamId`.
3. On decline → `file.accept{accept:false}`; no stream is opened.

## L3. Send bytes  `sendFile(transferId, source) -> Stream<Progress>`  *(sender)*
1. On `file.accept{accept:true}`, open the bulk stream: `ConnectionService.openStream(streamId)`.
2. Read `source` and chunk with the U1 `StreamChunker.chunk(streamId, data, 64 KiB)` — last frame
   carries `END_OF_STREAM` (BR-2).
3. Write frames in `sequence` order over the stream; after each frame emit `file.progress`
   `{ bytesSent, total, status: sending }` (BR-7 monotonic).
4. On the final frame emit `status: complete`. On any IO/stream error emit `status: failed` and abort
   the stream (BR-6, fail-closed).

## L4. Receive bytes  `receiveFile(offer) -> Stream<Progress>`  *(receiver)*
1. Feed each inbound `Frame` to U1 `StreamReassembler(streamId).accept(frame)`.
2. A wrong-stream / sequence gap / duplicate **faults** the transfer → drop, log security event,
   emit `status: failed`, do not write a partial file (BR-6, mirrors `StreamReassembler.fault`).
3. On `END_OF_STREAM` with `reassembler.complete`, verify reassembled byte count == declared `size`;
   mismatch → `failed`. On match, write bytes to `Destination/name` (BR-4) and emit `status: complete`.

## L5. Destination resolution  (FR-5.3, US-5.3)
- Read configured `Destination.path` from Settings (U10); default = platform Downloads.
- Compose final path from `path` + sanitized `name`; on name collision, de-duplicate (`name (1).ext`).
- Write is atomic where the platform allows (temp file + rename) so a failed transfer leaves no
  half-written file at the destination.

## L6. Direction symmetry
Both Mac→Android and Android→Mac use the identical L1–L5 flow with roles swapped — the protocol and
chunking are platform-neutral (US-5.1 / US-5.2). Bulk always rides the **LAN** link, never Bluetooth
(FR-5.4).

---

## Data flow (one transfer)
```
sender: offerFile ──file.offer──▶ receiver (UI accept) ──file.accept──▶ sender
sender: chunk(file) ──Frame[] on streamId (U3 mTLS)──▶ receiver: StreamReassembler ──▶ Destination
both:   TransferState ──file.progress(sending→complete|failed)──▶ UI
```

## Testable Properties (PBT-01)
| Property | Category | Statement |
|----------|----------|-----------|
| **Chunk/reassemble round-trip** (PBT-03) | Round-trip | `reassemble(chunk(data)) == data` for arbitrary byte arrays — empty, < 64 KiB, exact multiples, and non-multiples of 64 KiB. |
| **Chunk size invariant** (PBT-03) | Invariant | `sum(frame.length for frame in chunk(data)) == data.size`. |
| **End-of-stream invariant** (PBT-03) | Invariant | `chunk(data)` has exactly one `END_OF_STREAM` frame and it is the last. |
| **Sequence contiguity** (PBT-03) | Invariant | frame `sequence` values are `0..n-1`, contiguous and gap-free. |
| **Progress monotonicity** (PBT-03, advisory) | Invariant | successive `file.progress.bytesSent` is non-decreasing and never exceeds `total`. |

The chunk/reassemble core (`android/.../core/StreamAssembler.kt` — `StreamChunker` +
`StreamReassembler`) is pure and JVM-testable, and is U6's primary PBT surface (carried from U1 BR-20).
Offer/accept handshake and IO orchestration are I/O-bound — covered by example/integration tests, not PBT.
