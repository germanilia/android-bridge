# NFR Requirements — U4 Notifications

U4 is a thin feature plugin: a pure mapper + allowlist predicate on the phone, a renderer on the Mac,
riding U3's link. It owns no transport, storage engine, or scaling concern — those live in U1/U3.

---

## NFR-U4.1 Testability *(headline)*
- Round-trip PBT for the `notif.posted` payload (PBT-02) with a domain generator covering
  `pkg/title/text/postedAt`, including empty and Unicode strings (PBT-07).
- Invariant PBT for the allowlist filter (PBT-03): subset + exact-match property.
- Example-based tests pin a known notification → expected `notif.posted` and an allow/deny pair.

## NFR-U4.2 Performance
- Mapping + filtering is O(1) per notification, far under any human-perceptible bound; no explicit
  latency target. Bulk/throughput N/A (notifications are low-rate, small control messages).

## NFR-U4.3 Reliability / correctness
- Capture path is total: a notification either maps to a valid `notif.posted` or is dropped by the
  allowlist; no partial/unchecked message is sent (BR-1/BR-3).
- Graceful degradation when listener access is missing/revoked (BR-10 / NFR-5.2).

## NFR-U4.4 Security (Baseline ON — applicable rules)
| Rule | Status | How |
|------|--------|-----|
| SECURITY-05 (input validation) | Compliant | Per-type Schema validation of inbound `notif.posted` (BR-6). |
| SECURITY-13 (safe deserialization) | Inherited | U1 codec parses into typed `Message` via allowlisted registry. |
| SECURITY-15 (fail-closed) | Inherited | Drop malformed; link survives (BR-9). |
| SECURITY-03 (no-PII logging) | Compliant | `title`/`text` never logged; only `pkg`/`msgType`/sizes (BR-8). |
| SECURITY-01 (encrypt in transit) | Inherited | mTLS link from U3 carries all `notif.posted`. |
| SECURITY-01/-12 (encrypt at rest) | Compliant | Allowlist persisted via `SecureStore` (Keystore/Keychain), not plaintext. |
| SECURITY-06 (least privilege) | Compliant | Requests only notification-listener access; deny-by-default allowlist (BR-3). |
| SECURITY-10 (supply chain) | Deferred | Pinning/scan/SBOM handled at Build & Test (no new runtime deps). |
| SECURITY-02/-04/-07/-09/-11/-14 | N/A | No cloud/web tier, load balancer, HTTP headers, VPC, or alerting in a local plugin. |

## NFR-U4.5 Maintainability / portability
- Mapper stays free of Android types (`feature/Mappers.kt`) so logic is JVM-testable and portable.
- Read-only boundary keeps the protocol open for US-3.3 actions without reworking transport (NFR-6.2).

## Out of scope (asserted)
Availability, scaling, rate limiting, DR — N/A (local plugin). Permission prompting + toggle = U10.
