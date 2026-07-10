# NFR Requirements — U7 Clipboard

U7 is a **small feature** over U1 control messages and the U3 mTLS link. Its only pure logic is the
sync-mode decision and the payload mapper; the rest is OS clipboard I/O. Transport security,
availability, and reconnect live in U3, not here.

---

## NFR-U7.1 Testability *(headline NFR)*
- Round-trip property test on the `clip.update` payload: `decode(encode(m)) == m` (PBT-02; BR-10).
- Decision-table invariant on the policy: `shouldSend == (mode == AUTO) || userInitiated` across all
  inputs (PBT-03 / oracle; BR-11).
- Domain generators produce arbitrary clipboard text incl. empty / Unicode / boundary sizes (PBT-07);
  seeded + shrinking CI (PBT-08).
- Example tests pin the default-MANUAL behavior (copy alone does not send) and inbound-apply (no echo).

## NFR-U7.2 Performance
- Negligible: a single small control message per push; no streaming, no per-frame work. Bounded by
  the U1 control codec target (≤ ~1 ms encode/decode).

## NFR-U7.3 Reliability / correctness
- Fail-closed on malformed inbound `clip.update` (BR-7), consistent with the U1/U3 trust boundary.
- No echo loop when applying inbound updates (BR-4) — prevents clipboard ping-pong.
- Privacy-safe default: MANUAL push means nothing leaves the device without explicit user action
  (BR-1/BR-2 / NFR-1).
- Graceful degradation: if clipboard permission/access is unavailable, the feature reports unavailable
  and others keep working (NFR-5.2 / U10).

## NFR-U7.4 Security (Baseline ON — applicable rules)
| Rule | Applies to U7 | How |
|------|---------------|-----|
| SECURITY-01 (in transit) | Inherited (U3) | `clip.update` rides the mTLS LAN link (FR-6.3). |
| SECURITY-05 (input validation) | ✅ | `clip.update` validated against Schema before applying (BR-7). |
| SECURITY-13 (safe deserialization) | Inherited (U1) | Parsed via allowlisted registry; no unsafe deserialization. |
| SECURITY-15 (fail-closed) | ✅ | Malformed inbound → drop + log, keep link (BR-7). |
| SECURITY-03 (no-PII logging) | ✅ | Clipboard text never logged; `LinkLogger` drops `text` (BR-9). |
| SECURITY-06 (least privilege) | ✅ | Clipboard access requested only when the Clipboard feature is enabled (U10). |
| SECURITY-12 (at rest) | N/A | Clipboard content is not persisted by U7; only the sync-mode setting persists (U10). |
| SECURITY-10 (supply chain) | Deferred | Pinning/scan/SBOM at Build & Test. |
| SECURITY-02/-04/-07/-08/-09/-11/-14 | N/A | No cloud/web tier, server auth, or alerting in a P2P clipboard feature. |

## NFR-U7.5 Maintainability / portability
- `ClipboardSyncPolicy` + `Mappers.clipboard` are pure, platform-neutral, and dependency-free.
- ClipboardPlugin/Service depend only on `ConnectionService` (NFR-6.2). Identical API across
  Swift/Kotlin (readClipboard/applyClipboard/setSyncMode).

## Out of scope for U7 (asserted)
mTLS, send, heartbeat, reconnect → **U3**. Control codec/validation → **U1**. Sync-mode toggle UI +
persistence → **U10/U11/U12**. Non-text/large clipboard content → **U6**.
