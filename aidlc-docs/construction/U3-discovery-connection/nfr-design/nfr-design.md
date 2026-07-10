# NFR Design — U3 Discovery & Connection

How U3's NFRs are realized concretely. Cites SECURITY-xx rule IDs; N/A rules marked with rationale.
Infrastructure Design is **skipped** for all units (local P2P, no cloud).

---

## Security patterns

### Encryption in transit + peer authentication (SECURITY-01 / -06 / -08) — Owned
- **Mutual TLS (1.2+)** over the LAN. Each side presents its U2 cert; a custom trust callback
  (`X509TrustManager` on Android / `sec_protocol` verify block on Mac) accepts the peer **only** if
  its cert matches a **pinned fingerprint** (`PairingManager.isPinned`). Deny-by-default: unpinned →
  refuse (BR-1).
- A single mTLS session multiplexes control + all binary streams (AR1) — no unencrypted side channel.

### Fail-closed handling (SECURITY-15) — Owned
- `MessageRouter.route` re-validates and **drops** invalid/unrouted messages (`security.dropped_*`)
  while keeping the link (BR-3). `version_mismatch` → reject link (BR-2). Stream gap/dup/wrong-stream
  → **abort that stream only** via `StreamReassembler.fault` (BR-5). Errors never fail open.

### Input validation / safe deserialization (SECURITY-05 / -13) — Owned at boundary
- Decode + registry validation in U1; U3 re-checks defensively before dispatch (`validate`). Only
  registry `MessageType`s can be registered/routed (BR-4).

### No-PII logging (SECURITY-03) — Owned
- `LinkLogger` records event + `type`/`streamId`/`reason`; its forbidden-key filter strips any
  body/number/token/payload field (BR-12). Security events (refused peer, dropped msg, faulted
  stream) are logged (SECURITY-14 local equivalent — no cloud alerting).

### Hardening (SECURITY-09) — Partial
- Connect failures surface **generic** messages to the user; internal cert/socket detail stays in
  logs only.

### Supply chain (SECURITY-10) — Deferred
- Dependency pinning, vulnerability scan, SBOM at **Build & Test**.

### N/A (rationale)
SECURITY-02 (no load balancer/CDN), SECURITY-04 (no HTML endpoint), SECURITY-07 (no cloud VPC/SG),
SECURITY-11 rate-limiting (no public endpoint — peer is a single pinned device), SECURITY-14 cloud
alerting (local security events via `LinkLogger`).

## Reliability patterns (resiliency baseline NOT applied — NFR-5.3)
- **Reconnect**: the pure `ConnectionStateMachine` models `CONNECTED→RECONNECTING` on dropped
  heartbeats and back to `CONNECTED` after rediscovery, with ordinary retry/backoff and **no
  re-pair** (BR-8/-9). No circuit breakers / bulkheads (out of scope).
- **Fault isolation**: a faulted stream or dropped message never crashes the link (NFR-5.2 / BR-3/-5).
- **Background keep-alive**: Android `LinkForegroundService` (BR-10).

## Performance patterns
- Single persistent multiplexed session avoids per-message TLS setup (AR1); 64 KiB framing bounds
  per-frame work, keeping headroom under the U8 ~80 ms target (NFR-3.1).

## Testability pattern (PBT)
- Stream round-trip + chunking/state-machine invariants (PBT-03), domain generators (PBT-07),
  shrinking + seed logging (PBT-08).
- **Environment deviation**: no Xcode → Swift uses the seeded `PropertyHarness` (not SwiftCheck/
  XCTest) for the portable pieces; meets PBT-09 intent. The Mac transport itself can't be built here.
  Kotlin uses Kotest; `NsdManager`/mTLS/foreground need a device. On a machine with Xcode, swap to
  SwiftCheck + XCTest unchanged.

## Logical components (no infrastructure)
`DeviceDiscovery` (B1) · `ConnectionManager` (B3, owns the mTLS `PeerSession`) · `MessageRouter`
(B4) · `StreamChunker`/`StreamReassembler` · `ConnectionStateMachine` · `LinkForegroundService` (D2,
Android) · services `DiscoveryService`/`ConnectionService`/`MessageRouter` facade. All in-process; no
queues, brokers, or cloud services.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
