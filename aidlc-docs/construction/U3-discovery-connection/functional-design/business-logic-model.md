# Business Logic Model — U3 Discovery & Connection

Technology-agnostic flows for LAN discovery, mTLS link ownership, multiplexed streams, heartbeat/
reconnect, and inbound routing. Builds on U1 (codecs/validation) and U2 (pinned trust). Orchestrated
by `DiscoveryService` (S1), `ConnectionService` (S3), and the `MessageRouter` facade (S4).

---

## L1. Discover peer  `startBrowsing() / startAdvertising(identity)`
1. Advertise this device + browse for the paired peer via **mDNS** (`NsdManager` on Android,
   `NWBrowser`/`NWListener` on Mac), service type `_androidbridge._tcp.`.
2. On a resolved service → build `Endpoint{host, port}` → hand to `ConnectionService.connect` (US-2.1).
3. Emit `START_DISCOVERY` / `PEER_FOUND` to the `ConnectionStateMachine`.

## L2. Connect (mTLS)  `connect(endpoint)`  *(trust boundary — fail-closed)*
1. Open a TLS connection to `endpoint`; present this device's cert (from U2 keypair).
2. Validate the peer cert against the **pinned fingerprint** (`PairingManager.isPinned`). An
   unpinned/unknown peer → **refuse** (CC-SEC / SECURITY-06/-08), log a security event (BR-1).
3. On success → `CONNECTED`; expose `send(message)` and `openStream(streamId)` to feature services.

## L3. Route inbound  `route(message)`  *(fail-closed)*
1. Decode happens in U1 (`MessageCodec.decode`) — already validated; `route` **re-validates**
   defensively (`validate`).
2. Invalid → drop, `security.dropped_invalid` (reason), keep the link (BR-3).
3. No handler for `type` → drop, `security.dropped_unrouted`, keep the link (BR-3).
4. Otherwise dispatch to the registered plugin handler. `version_mismatch` surfaced from decode →
   **reject the link** (BR-2, per U1 D-Q2).

## L4. Binary streams  `openStream(streamId) -> Stream`
1. Producer uses `StreamChunker.chunk(streamId, data)` → ordered frames (last `END_OF_STREAM`).
2. Frames ride the mTLS session multiplexed with control messages (single session, AR1).
3. Consumer feeds frames to `StreamReassembler`; a gap/dup/wrong-stream **faults that stream only**
   (abort + security event), other streams + control keep flowing (BR-5 / SECURITY-15).

## L5. Heartbeat & auto-reconnect
1. Periodic `link.heartbeat`; missing beats → `LINK_DROPPED`.
2. `ConnectionStateMachine`: `CONNECTED --LINK_DROPPED--> RECONNECTING`; rediscover + reconnect when
   reachable again, with no re-pairing (FR-2.4 / US-2.4). Ordinary retry/backoff — **resiliency
   baseline NOT applied** (NFR-5.3).
3. State changes are surfaced to the UI (US-2.3).

## L6. Keep-alive (Android)
`LinkForegroundService` runs the link while backgrounded with an ongoing notification (FR-2.2 /
US-2.2); foreground-service type `connectedDevice`.

---

## Data flow (steady state)
```
peer ──mTLS──▶ MessageCodec.decode (U1) ──▶ MessageRouter.route ──by type──▶ plugin
peer ──mTLS binary──▶ Frames ──▶ StreamReassembler ──bytes──▶ feature
ConnectionStateMachine ──state──▶ menu-bar / Compose status
```

## Testable Properties (PBT-01)
| Property | Category | Statement |
|----------|----------|-----------|
| Stream round-trip (PBT-03) | Round-trip | `reassemble(chunk(data)) == data` for all byte arrays, across chunk sizes. |
| Chunking invariant (PBT-03) | Invariant | Σ frame `length` == `data.size`; sequences are `0..n` contiguous; only the last frame sets `END_OF_STREAM`. |
| State-machine legality (PBT-03) | Invariant | For any event sequence, `state` stays within `ConnectionState`; no illegal transition (e.g. `PEER_FOUND` only advances from DISCOVERING/RECONNECTING). |

`StreamChunker`, `StreamReassembler`, and `ConnectionStateMachine` are **pure / JVM-testable**.
mTLS handshake, mDNS resolution, sockets, and the foreground service are **IO** — exercised on-device,
not via PBT. Kotlin uses Kotest property testing; the Swift port uses the seeded `PropertyHarness`.
