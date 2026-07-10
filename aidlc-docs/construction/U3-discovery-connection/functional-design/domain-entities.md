# Domain Entities — U3 Discovery & Connection

Technology-agnostic model for finding the peer, owning the secure link, and routing inbound traffic.
Implemented per platform: Kotlin (`android/app/.../core/` + `.../android/`) and Swift (`mac/`, not
yet written). Stories: US-2.1, US-2.2, US-2.3, US-2.4, US-10.3. Depends on U1, U2.

---

## E1. Endpoint
A LAN address for the peer, produced by discovery and consumed by connection.

| Field | Type | Notes |
|-------|------|-------|
| `host` | string | Resolved IP/hostname (mDNS). |
| `port` | int | TCP port for the mTLS listener. |

## E2. ConnectionState
Link lifecycle surfaced to the UI (FR-2.3). Mirrors the real Kotlin enum.

`DISCONNECTED · DISCOVERING · CONNECTING · CONNECTED · RECONNECTING`

## E3. ConnectionStateMachine
Pure state machine driving the lifecycle, incl. auto-reconnect (FR-2.4). Events:
`START_DISCOVERY · PEER_FOUND · CONNECTED · LINK_DROPPED · DISCONNECT_REQUESTED`. The transport
drives events; the UI observes `state`. Side-effect-free → JVM-testable.

## E4. Stream
A logical binary channel multiplexed on the single mTLS session, keyed by `streamId` (from the U1
`FrameHeader`). Carries file/screen bulk data via `Frame`s (U1 E4).

## E5. StreamChunker / StreamReassembler
- `StreamChunker.chunk(streamId, data, chunkSize=64 KiB)` → ordered `Frame`s, last flagged
  `END_OF_STREAM`. Pure.
- `StreamReassembler(streamId).accept(frame)` → enforces sequence ordering; a wrong-stream / gap /
  duplicate **faults** the stream (returns false + security event). `result()` yields the bytes.

## E6. RouteRegistration
Maps a `MessageType` → handler in the `MessageRouter` (B4). `register/unregister/route`.
`route(message)` re-validates (U1 `validate`) then dispatches; drops unknown/unrouted (fail-closed).

## E7. Heartbeat
Periodic `link.heartbeat` (U1 registry type) used to detect a dead link and trigger
`LINK_DROPPED` → `RECONNECTING`. (Liveness only; ordinary retry — resiliency baseline NOT applied.)

## E8. PeerSession (logical)
The active authenticated link: the pinned `PairedDevice` (from U2), the mTLS channel, the control
message stream, and any open binary `Stream`s. Owned by `ConnectionManager` (B3).

---

## Relationships
```
DeviceDiscovery ──finds──▶ Endpoint ──▶ ConnectionManager.connect ──mTLS vs pinned cert──▶ PeerSession
PeerSession ──control msgs──▶ MessageRouter.route ──by type──▶ plugin (U4–U10)
PeerSession ──binary──▶ Stream ──Frames──▶ StreamReassembler ──bytes──▶ feature
ConnectionStateMachine ──state──▶ UI (menu-bar / Compose)
```

## Out of scope for U3 (owned elsewhere)
- Envelope/frame codecs, validation, type registry → **U1**.
- Keypair, cert pinning, trusted list → **U2** (U3 *reads* the pin to authenticate).
- Per-feature payload semantics → feature units (**U4–U9**). Per-feature toggles → **U10**.
