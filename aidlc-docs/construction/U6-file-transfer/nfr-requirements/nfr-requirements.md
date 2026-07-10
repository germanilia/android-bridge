# NFR Requirements — U6 File Transfer

U6 is a **bulk I/O feature** built on U1 framing and the U3 mTLS stream. Its only pure, deterministic
core is the chunk/reassemble math (carried from U1); the rest is file I/O and stream orchestration.
Transport security, availability, and reconnect live in U3, not here.

---

## NFR-U6.1 Testability *(headline NFR)*
- Round-trip + invariant property tests on chunk/reassemble: `reassemble(chunk(data)) == data`,
  total-length preserved, single trailing `END_OF_STREAM`, contiguous sequences (PBT-03; BR-12/-13).
- Domain generators produce arbitrary byte arrays across sizes — empty, sub-chunk, exact-multiple,
  and non-multiple of 64 KiB (PBT-07); seeded + shrinking CI (PBT-08).
- Example/integration tests pin the offer→accept→stream→write happy path and the fault path
  (gap/dup → `failed`, no partial file) (PBT-10 complement).

## NFR-U6.2 Performance
- Chunking/reassembly is O(n) over file bytes with 64 KiB frames; per-frame codec cost is bounded by
  the U1 target (≤ ~2 ms / 64 KiB frame). Throughput is LAN-bound, not CPU-bound.
- Progress events are coalesced (per-frame or time-bounded) so UI updates don't dominate the transfer.

## NFR-U6.3 Reliability / correctness
- Fail-closed: gap/dup/wrong-stream faults the transfer and writes no partial file (BR-6).
- Atomic destination writes (temp + rename) so a failure never leaves a corrupt file (BR-9).
- Completion is verified against the declared `size` before the file is surfaced as done (BR-4).
- Graceful degradation: if storage permission/destination is unavailable, the transfer reports
  `failed` and other features keep working (NFR-5.2 / U10).

## NFR-U6.4 Security (Baseline ON — applicable rules)
| Rule | Applies to U6 | How |
|------|---------------|-----|
| SECURITY-01 (in transit) | Inherited (U3) | Bulk + control ride the mTLS LAN link (FR-5.4). |
| SECURITY-05 (input validation) | ✅ | `file.offer`/`file.accept`/`file.progress` validated against Schema; `name` sanitized (BR-5). |
| SECURITY-13 (safe deserialization) | Inherited (U1) | Control parsed via allowlisted registry; frames length-checked. |
| SECURITY-15 (fail-closed) | ✅ | Fault → drop stream, `failed`, no partial write (BR-6). |
| SECURITY-03 (no-PII logging) | ✅ | Names/contents never logged; only ids/sizes/reasons (BR-11). |
| SECURITY-06 (least privilege) | ✅ | Storage/file access scoped to the configured destination only. |
| SECURITY-12 (at rest) | Deferred | Destination path persists via U10 SecureStore/settings. |
| SECURITY-10 (supply chain) | Deferred | Pinning/scan/SBOM handled at Build & Test. |
| SECURITY-02/-04/-07/-08/-09/-11/-14 | N/A | No cloud/web tier, auth, or alerting in a P2P file feature. |

## NFR-U6.5 Maintainability / portability
- Chunk/reassemble core is platform-neutral and dependency-free (reuses U1 `StreamAssembler`).
- FileTransferPlugin/Service depend only on `ConnectionService` (streams) — no transport coupling
  (NFR-6.2). API shape identical across Swift/Kotlin (offer/accept/send/receive/setDestination).

## Out of scope for U6 (asserted)
mTLS, stream multiplexing, heartbeat, auto-reconnect → **U3**. Frame codec + ordering invariant →
**U1**. Drag-and-drop / progress UI / destination picker → **U11/U12**; persistence → **U10**.
