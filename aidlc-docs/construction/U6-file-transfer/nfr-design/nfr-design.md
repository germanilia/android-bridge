# NFR Design — U6 File Transfer

Concrete patterns realizing the U6 NFRs and the applicable Security Baseline rules. Infrastructure
Design is **skipped** for this project (local P2P, no cloud) — there are no queues, load balancers,
or cloud resources to design.

---

## Security pattern realization (Baseline ON)
| Rule | Realization in U6 | Status |
|------|-------------------|--------|
| SECURITY-01 (encryption in transit) | All `file.*` control + bulk frames travel only the U3 mTLS LAN session; no plaintext, no Bluetooth path (FR-5.4). | Inherited (U3) |
| SECURITY-05 (input validation) | `file.offer`/`file.accept`/`file.progress` validated against their Schema (required fields, size caps); offered `name` sanitized to a bare filename (BR-5) before path composition. | Compliant |
| SECURITY-13 (safe deserialization) | Control parsed via the U1 allowlisted registry; frame headers length-checked before slicing — no unsafe/native deserialization of peer bytes. | Inherited (U1) |
| SECURITY-15 (fail-closed) | Sequence gap/dup/wrong-stream → `StreamReassembler` faults → drop stream, emit `failed`, write no partial file (BR-6); size-mismatch on `END_OF_STREAM` → `failed` (BR-4). | Compliant |
| SECURITY-03 (no-PII logging) | `LinkLogger` allow-listed fields only — `transferId`, `streamId`, sizes, sequence, reason; file names/contents never logged (BR-11). | Compliant |
| SECURITY-06 (least privilege) | File access scoped to the configured Destination folder; storage permission requested only when the Files feature is enabled (U10). | Compliant |
| SECURITY-12 (encryption at rest) | Only the Destination **path** persists (via U10 SecureStore/settings); no file contents cached at rest by U6. | Deferred (U10) |
| SECURITY-10 (supply chain) | No new runtime deps beyond platform file I/O; pinning + scan + SBOM at Build & Test. | Deferred (Build&Test) |
| SECURITY-02 / -04 / -07 / -08 / -09 / -11 / -14 | No cloud/web tier, server auth, network intermediary, or alerting in a P2P file feature. | N/A |

## Performance patterns
- **Streaming, bounded memory**: send/receive operate frame-by-frame (64 KiB) — never load the whole
  file into memory; reassembly streams to a temp file, not a byte buffer, for large transfers.
- **Progress coalescing**: emit `file.progress` per-frame or on a small time interval to keep UI
  updates off the hot path; throughput stays LAN-bound (NFR-U6.2).
- **O(n) chunk math**: `StreamChunker` is linear in file size with no per-byte allocation beyond the
  current slice.

## Reliability patterns
- **Atomic write**: receive to `Destination/.name.partial`, fsync, then rename to final on success
  (BR-9) — a failed/aborted transfer leaves no corrupt artifact.
- **Total accounting**: completion gated on `END_OF_STREAM` + `complete` + byte-count == `size`
  (BR-4); any mismatch is `failed`, not silently truncated.
- **Graceful degradation**: missing storage permission/destination → `failed` + fix-it hint (U10),
  no crash, other features unaffected (NFR-5.2).

## Misuse / abuse consideration (SECURITY-11 design intent)
- A malicious peer cannot path-traverse via `name` (sanitization, BR-5) and cannot exhaust the link
  with an oversized control message (U1 1 MiB cap) or an out-of-order frame flood (fault-and-abort,
  BR-6). Bytes flow only after explicit user accept (BR-1).

## Logical components (no infrastructure)
`FileTransferPlugin` (C3) + `FileTransferService` (S5) on each app, depending only on
`ConnectionService` (streams) and U10 settings for the destination. No external infrastructure
components (queues/caches/circuit breakers) — local P2P.
