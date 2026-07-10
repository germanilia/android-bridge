# Business Rules — U3 Discovery & Connection

Decision rules and constraints for discovery, the secure link, and routing. IDs (BR-x) referenced by
NFR Design and Code Generation. Stories US-2.1..2.4, US-10.3.

---

## Trust & connection (CC-SEC)
- **BR-1**: A connection is accepted **only** if the peer cert matches a **pinned** fingerprint
  (`PairingManager.isPinned`, from U2). An unpinned/unknown peer is **refused** + security event
  (FR-1.3 / SECURITY-06/-08).
- **BR-2**: A `version_mismatch` reported by U1 decode → **reject the link** (no negotiation in v1,
  per U1 D-Q2 / BR-15).

## Routing (fail-closed, SECURITY-15)
- **BR-3**: An invalid or unrouted control message → **drop + log** (`security.dropped_invalid` /
  `security.dropped_unrouted`), **keep the link open** — a single bad message does not tear down the
  connection (mirrors `MessageRouter.route`).
- **BR-4**: `register` rejects unknown `MessageType`s — only registry types (U1) can be routed.

## Streams (ordering invariant)
- **BR-5**: Frames on a `streamId` must arrive in contiguous `sequence` order; a gap, duplicate, or
  wrong-stream frame **faults that stream only** (abort + security event), leaving control + other
  streams alive (mirrors `StreamReassembler`). The last frame sets `END_OF_STREAM`.
- **BR-6**: A single mTLS session multiplexes control + all binary streams (AR1) — no second socket.

## Discovery
- **BR-7**: Peers are found by **mDNS** service type `_androidbridge._tcp.` — no manual IP entry
  (FR-2.1). Only generic public APIs (`NsdManager` / `NWBrowser`) — no Samsung APIs (NFR-6.1 / US-10.3).

## Liveness & reconnect (resiliency baseline NOT applied)
- **BR-8**: Missing heartbeats → `LINK_DROPPED` → `RECONNECTING`; the link re-establishes when both
  devices are reachable, **without re-pairing** (FR-2.4 / US-2.4).
- **BR-9**: Reconnect is ordinary retry/backoff — the AWS resiliency baseline is **not** enforced
  (NFR-5.3); this is a local link, not a distributed cloud workload.
- **BR-10**: The Android link runs under a **foreground service** with an ongoing notification while
  backgrounded (FR-2.2 / US-2.2).

## State surfacing
- **BR-11**: Connection state (`DISCONNECTED/DISCOVERING/CONNECTING/CONNECTED/RECONNECTING`) is shown
  on the Mac menu-bar and the Android app (FR-2.3 / US-2.3), driven by the pure
  `ConnectionStateMachine`.

## Privacy (CC-PRIV / SECURITY-03)
- **BR-12**: Connection/routing logs carry only `type`, `streamId`, `reason`, and event name — never
  payloads, numbers, or keys (`LinkLogger` forbidden-field filter).

## Property-based testing (PBT partial)
- **BR-13 (PBT-03)**: `reassemble(chunk(data)) == data`; chunking + state-machine invariants hold
  (see business-logic-model "Testable Properties").

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-2.1 (auto-discover) | BR-7 |
| US-2.2 (background link) | BR-10 |
| US-2.3 (status) | BR-11 |
| US-2.4 (auto-reconnect) | BR-8, BR-9 |
| US-10.3 (generic Android) | BR-7 |
| CC-SEC (only pinned peers) | BR-1, BR-2 |
| CC-VALID / SECURITY-05/-13/-15 | BR-3, BR-4, BR-5 |
| CC-PRIV / SECURITY-03 | BR-12 |
