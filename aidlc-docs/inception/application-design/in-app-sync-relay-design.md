# In-App Sync Relay Application Design

## Architecture Decision
Use a stateless Kotlin/JVM relay exposed as HTTPS/WSS through the existing private Tailscale and Nginx Proxy Manager setup. Both apps maintain outbound WSS connections. Direct Bonjour/NSD plus pinned TLS remains preferred; relay activates only after the bounded direct attempt fails.

The relay stores enrollment and device-routing configuration only. It never queues user payload. Offline replay is endpoint-owned through durable operation journals and content-addressed spool files.

## Components

### Shared protocol
- `RelayEnvelope`: authenticated routing metadata plus one encrypted/encoded Android Bridge frame.
- `DeliveryMetadata`: durable sequence, operation ID, replay classification, and acknowledgement cursor.
- `SyncOperation`: immutable whole-file snapshot or tombstone with actor, sequence, path, base hash, result hash, blob hash, size, and media type.
- Additive capability negotiation keeps protocol version 1 compatible with direct-only peers.

### Relay service
- Enrollment HTTP endpoints issue one-time setup and invitation flows.
- Device credentials are unique, revocable, hashed at rest, and scoped to one workspace/pair.
- WSS registry maps authenticated device IDs to current connections.
- Frames are validated for size and routing metadata, then forwarded with backpressure.
- If the destination is absent, the relay rejects the frame immediately so the sender retains its local operation.
- Health routes expose no sensitive state.
- Structured logs include timestamp, request ID, device ID, result, byte count, and latency only.

### Endpoint durable delivery
- One append-only operation journal per local actor.
- One persisted receive cursor/deduplication index per peer.
- Content-addressed blobs for notes, files, meeting photos, and phone-origin meeting audio awaiting Mac acknowledgement.
- Write operation metadata and owned blob before applying/sending.
- Cumulative acknowledgement advances only after durable and idempotent peer handling.
- No automatic retention cutoff. Disk-full blocks a new durable mutation before canonical state changes.

### Second Brain synchronization
- Complete-file snapshots, not character patches or CRDTs.
- Hash preconditions determine apply versus conflict; wall clocks never select a winner.
- Matching result hash is an idempotent no-op.
- Matching base hash permits replacement.
- Mismatched base hash preserves incoming bytes as a visible Bridge conflict sibling.
- Journals remain outside Syncthing roots.
- External filesystem scans create observed revisions; hashes suppress relay/Syncthing echo loops.

### Meeting synchronization
- Stable meeting IDs own generated Markdown and photo collections.
- Mac-to-phone projection includes metadata, summary, transcript, Q&A, status, recording count, and validated JPEG/PNG photos.
- Mac-local audio is never offered to the phone.
- Phone-origin meeting audio may use the durable transfer spool to reach the Mac, then is retained only in the configured Mac meeting directory after acknowledgement.

### Android client
- OkHttp WSS transport, encrypted settings, and coroutine-backed inbound channel.
- Direct-first selector with one active session and generation token to prevent stale-session adoption.
- App-private durable journal/blob store.
- SAF compare-and-set note application with visible conflict copies and read-back verification.
- Foreground service owns reconnect lifecycle without a permanent wake lock.

### macOS client
- Native `URLSessionWebSocketTask` transport and Keychain credentials.
- Direct-first selector using current Network.framework connection.
- Application Support durable journal/blob store with atomic replacements.
- Sleep closes sessions and pauses reconnect; wake restarts LAN-first selection and replay.

## Connection State Machine
1. Disabled: relay configuration absent or disabled.
2. SearchingDirect: Bonjour/NSD discovery and bounded direct attempt.
3. DirectConnected: direct TLS owns routing; relay messages are not applied.
4. ConnectingRelay: open authenticated WSS after direct failure.
5. RelayConnected: existing router receives relayed protocol messages.
6. Replaying: exchange cursors and replay missing durable operations before new durable sends.
7. Paused: peer absent, device asleep, or network unavailable; local operations continue journaling.
8. Reconnecting: bounded exponential backoff with jitter, retrying direct first.

A monotonic session generation prevents simultaneous direct/relay callbacks from adopting two sessions. A healthy relay session is not hot-migrated; the next reconnect retries direct first.

## Durable Delivery Rules
- At-least-once transport; idempotent application provides effectively-once observable state.
- Acknowledgements cannot move backward or beyond the sender high-water mark.
- Invalid cursor or acknowledgement closes the session without deleting records.
- Clipboard coalesces unacknowledged values to the latest value.
- Call state stores latest snapshot; call actions never replay.
- Screen frames, gestures, heartbeats, and ringing actions are live-only.
- Files and media copy into owned spool before durable queueing.

## Relay Deployment
- Kotlin/JVM 17 and Ktor CIO.
- Pinned Gradle dependencies and lock/verification metadata.
- Non-root pinned JRE image, read-only root filesystem, dropped capabilities, no host ports.
- Named volume contains configuration/credential hashes only.
- Attach to `system_default`; NPM forwards `relay.homeserver` to `android-bridge-relay:8080` with WebSockets enabled.
- Production clients require WSS with a trusted internal certificate or Tailscale Serve hostname; no plaintext WebSocket fallback.

## Testable Properties
- Serialization round trip for every relay/delta model.
- Decode rejects malformed/oversized records before allocation.
- Cursors are monotonic.
- Duplicate operation application is idempotent.
- Resume returns exactly the unacknowledged suffix.
- Conflict handling preserves both byte sequences.
- Chunking and reassembly preserve exact bytes.
- Mutation of digest/chunk/order cannot commit a blob.
- Random disconnect/reconnect schedules converge to the uninterrupted model.
- Compaction never removes unacknowledged operations.
- Direct/relay duplicate delivery causes one observable effect.

## Safety Findings Addressed Before Exposure
- Add receive-length checks to Android before allocation.
- Add declared-length and receive-buffer bounds to macOS.
- Never let relay reachability replace peer/workspace authorization.
- Never replay call actions or remote-control input.
- Never log relay payloads or sensitive metadata.

## Extension Compliance
- Security Baseline: disabled by user for this private increment; minimum safety boundaries above are mandatory.
- Resiliency Baseline: disabled.
- Property-Based Testing: compliant design targets PBT-01 through PBT-10.
