# NFR Requirements — U5 SMS / MMS

U5 is a read-only feature plugin: Telephony reads + a pure mapper + a pure thread-grouping transform on
the phone, a threaded renderer on the Mac, riding U3's link. No transport/storage engine of its own
(U1/U3); it may cache thread history through `SecureStore`.

---

## NFR-U5.1 Testability *(headline)*
- Round-trip PBT for `sms.received`/`sms.thread` payloads (PBT-02) with generators covering
  `threadId/address/body/receivedAt`, empty + Unicode bodies (PBT-07).
- Invariant PBT for `ConversationGrouping` (PBT-03): count-preservation, single-thread membership,
  per-thread ordering.
- Example tests pin a known SMS → `sms.received` and a small message list → expected grouped threads.

## NFR-U5.2 Performance
- Mapping is O(1) per message; grouping is O(n log n) over a thread's messages — negligible for
  realistic histories. No explicit latency target; bulk/throughput N/A (control-message scale; MMS
  bytes ride frame streams handled by U6).

## NFR-U5.3 Reliability / correctness
- Read path is total: a message either maps to a valid `sms.received` or is dropped; grouping never
  drops or duplicates a message (BR-3).
- Graceful degradation: SMS perm missing → feature unavailable; contacts perm missing → raw addresses
  (BR-9 / NFR-5.2).

## NFR-U5.4 Security (Baseline ON — applicable rules)
| Rule | Status | How |
|------|--------|-----|
| SECURITY-05 (input validation) | Compliant | Per-type Schema validation of inbound `sms.*` (BR-7). |
| SECURITY-13 (safe deserialization) | Inherited | U1 codec → typed `Message` via allowlisted registry. |
| SECURITY-15 (fail-closed) | Inherited | Drop malformed; link survives (BR-7). |
| SECURITY-03 (no-PII logging) | Compliant | `body`/`address`/contact names never logged (BR-5). |
| SECURITY-01 (encrypt in transit) | Inherited | mTLS link (U3) carries all `sms.*`. |
| SECURITY-01/-12 (encrypt at rest) | Compliant | Any cached thread history persisted via `SecureStore`, never plaintext. |
| SECURITY-06 (least privilege) | Compliant | Requests only SMS read + optional contacts read (BR-8). |
| SECURITY-10 (supply chain) | Deferred | Pin/scan/SBOM at Build & Test; no new runtime dep. |
| SECURITY-02/-04/-07/-09/-11/-14 | N/A | No cloud/web tier, intermediary, HTTP, VPC, or alerting plane. |

## NFR-U5.5 Maintainability / portability
- Mapper + grouping stay free of Android types (`feature/Mappers.kt`) → JVM-testable, portable.
- Read-only boundary + reserved `sms.send` keep the protocol open for US-4.3 without transport rework
  (NFR-6.2 / FR-4.4).

## Out of scope (asserted)
Availability, scaling, rate limiting, DR — N/A (local plugin). Perms/toggle = U10; MMS byte transport = U6.
