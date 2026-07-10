# NFR Requirements — U3 Discovery & Connection

U3 owns the **live secure link**: mDNS discovery, mTLS session, multiplexed streams, heartbeat/
reconnect, and inbound routing. This is where most transport-level security and reliability live.

---

## NFR-U3.1 Security (Baseline ON — applicable rules) *(headline)*
| Rule | Applies | How |
|------|---------|-----|
| SECURITY-01 (encryption in transit) | ✅ Owned | All device-to-device traffic over **mutual TLS (1.2+)** on the LAN (NFR-1.2). |
| SECURITY-06/-08 (least privilege / access control) | ✅ Owned | Deny-by-default: only **pinned** mTLS peers are accepted (BR-1); unpinned refused. |
| SECURITY-15 (fail-closed) | ✅ Owned | Invalid/unrouted msg → drop+log, keep link; version mismatch → reject; stream fault → abort that stream (BR-2/-3/-5). |
| SECURITY-05/-13 (input validation / safe deser) | ✅ Owned at boundary | `MessageRouter.route` re-validates before dispatch; decode/registry from U1. |
| SECURITY-03 (no-PII logging) | ✅ Owned | Link/route logs carry only `type`/`streamId`/`reason` (BR-12). |
| SECURITY-12 (credential mgmt) | ◻ Inherited | Cert/keypair + pinning owned by U2; U3 uses them. |
| SECURITY-10 (supply chain) | ⏳ Deferred | Pinning + scan + SBOM at Build & Test. |
| SECURITY-09 (hardening) | ◻ Partial | Generic user-facing errors only (no internal detail on connect failures). |
| SECURITY-02/-04/-07/-11/-14 | N/A | No load balancer/CDN, HTML endpoint, cloud VPC, public rate-limited API, or cloud alerting — local P2P. |

## NFR-U3.2 Performance / latency
- The link must add negligible overhead over the U1 codec budget so it stays well under the screen-
  mirroring frame budget (NFR-3.1, ~80 ms target owned by U8). Single multiplexed session avoids
  per-message connection cost (AR1).
- Frame chunking at 64 KiB (U1 default) bounds per-frame work.

## NFR-U3.3 Reliability (baseline engineering; resiliency extension NOT applied)
- Recovers from transient Wi-Fi drops via reconnect/retry (NFR-5.1 / BR-8/-9). No re-pair needed.
- A single malformed message or faulted stream does not crash or tear down the link (NFR-5.2 / BR-3/-5).
- AWS resiliency baseline explicitly **not** enforced (NFR-5.3) — local link.

## NFR-U3.4 Testability (PBT partial)
- Stream round-trip + chunking invariants + state-machine legality (PBT-03) over domain generators
  (PBT-07), seeded + shrinking (PBT-08), framework per NFR (PBT-09). mTLS/mDNS/sockets are IO →
  example/on-device tests, not PBT.

## NFR-U3.5 Privacy & maintainability
- No data leaves the two paired devices (NFR-1.1); transport encrypted (NFR-1.2).
- Transport cleanly separated from feature code so features add without reworking it (NFR-6.2);
  generic Android APIs only (NFR-6.1).

## Out of scope for U3 (asserted)
Codecs/validation (U1), trust material (U2), per-feature semantics (U4–U9), per-feature toggles (U10).
Horizontal scaling / availability SLAs / DR — N/A (local link, no service).
