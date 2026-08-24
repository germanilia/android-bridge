# In-App Sync Relay Requirements

## Intent Analysis
- **Request type**: New cross-system feature plus transport enhancement.
- **Scope**: Android app, macOS app, shared protocol, self-hosted relay, local persistence, settings, deployment, and tests.
- **Complexity**: Comprehensive. The feature changes connectivity, delivery guarantees, conflict behavior, and handling of sensitive user data.
- **User intent**: Android Bridge must behave as connected when the Mac and phone are on different networks. A private home-server relay is optional; direct LAN remains preferred.

## Confirmed Decisions
1. The relay covers everything Android Bridge handles: notes, meeting text/photos, clipboard, files, notifications, SMS/call state, protocol events, and live feature traffic.
2. Direct LAN is preferred. Failure or loss of LAN connectivity automatically falls back to relay.
3. If either app sleeps or is offline, synchronization pauses. Each endpoint keeps its local state/deltas indefinitely and resumes from the last acknowledged position after reconnecting.
4. The relay does not provide an offline user-payload queue.
5. Meeting metadata, summaries, transcripts, questions, status, counts, and photos may sync. Audio remains only in its existing Mac location.
6. Relay endpoints are configurable. The first deployment uses private Tailscale connectivity.
7. The relay ships as a Docker Compose service.
8. Enrollment uses a one-time server setup code and per-device credentials.
9. Relay URL and credentials are configured separately in each app.
10. Conflicting offline note edits preserve both versions for manual resolution.
11. The previously reported Brain search issue is withdrawn; no folder-search change is requested in this increment.
12. The resiliency extension is disabled. Full property-based testing applies. The full security extension is disabled for this private Tailscale deployment, but minimum transport authentication, TLS, secret storage, validation, and safe logging remain mandatory.

## Functional Requirements

### RELAY-FR-01: Optional relay mode
Both apps shall expose relay settings containing enabled state, configurable endpoint, enrollment action, connection status, and credential removal. Relay mode shall remain disabled until explicitly configured.

### RELAY-FR-02: Direct-first connection
Both apps shall continue Bonjour/NSD direct discovery and direct pinned-TLS connection. When no direct session is established within the existing bounded connection attempt, or a direct session is lost, each configured app shall connect to the relay automatically. A healthy direct session shall replace a relay session without duplicating delivered messages.

### RELAY-FR-03: Transparent live relay
When both apps are online, the relay shall carry the existing length-framed Android Bridge protocol and live traffic in both directions. Existing feature handlers shall not need feature-specific relay branches.

### RELAY-FR-04: Enrollment and credentials
The relay shall create a single-use, short-lived setup code. Each app exchanges that code for a unique device ID and revocable device credential. Credentials shall be stored in Android encrypted preferences and macOS Keychain. Setup codes and credentials shall never be committed or logged.

### RELAY-FR-05: Peer isolation
The relay shall pair only explicitly authorized Mac and Android device IDs. A device may exchange frames only with its paired peer. Unknown, revoked, malformed, oversized, or cross-pair traffic shall be rejected.

### RELAY-FR-06: Local durable delta outbox
Each app shall persist asynchronous outbound operations locally before reporting them queued. Operations remain until the peer acknowledges their unique operation ID. Restart, sleep, connection loss, direct-to-relay switching, and repeated delivery shall not lose or duplicate an acknowledged operation.

### RELAY-FR-07: Resume protocol
On every session, peers shall exchange durable synchronization cursors and replay only unacknowledged operations. Duplicate operation IDs shall be idempotently acknowledged without reapplying their effects.

### RELAY-FR-08: Synchronized data
The durable operation model shall cover:
- clipboard updates;
- received notifications and SMS/call-state events where platform policy permits retention;
- file transfer metadata and owned spool bytes;
- Second Brain note create/update/delete operations;
- meeting text projection and meeting photos;
- other asynchronous protocol messages classified as replay-safe.

Ephemeral screen frames, remote-control gestures, ringing/answer commands, and other time-sensitive actions shall use live relay transport only and shall not replay after reconnect.

### RELAY-FR-09: Second Brain coexistence
The relay sync path shall coexist with current local folders and optional Syncthing. Every relay note operation shall include path, content digest, base digest, origin device, and operation ID. Applying the same content received through Syncthing and relay shall be idempotent.

### RELAY-FR-10: Conflict preservation
If an incoming note update's base digest differs from the current local digest and the incoming content is not already present, the app shall preserve both versions using the existing conflict-file convention and expose the conflict in Brain. It shall not silently overwrite either edit.

### RELAY-FR-11: Meeting boundary
Meeting relay projection from Mac to phone may contain text metadata and photos. It shall exclude Mac-local audio bytes, audio filenames, and absolute local audio paths. Audio captured by the phone may transit the live relay or endpoint-local durable spool to the Mac for processing, but the relay shall never retain it and the acknowledged recording shall live only in the configured Mac meeting directory. Meeting photos and phone-origin audio queued for transfer shall use app-owned spool copies so source cleanup cannot corrupt an unacknowledged transfer.

### RELAY-FR-12: File transfer resume
Durable file and photo operations shall be chunked, bounded per frame, digest-verified, and resumable from the last acknowledged chunk. Temporary and completed spool data shall be removed only after verified peer acknowledgement or explicit user cancellation.

### RELAY-FR-13: Relay service operations
The relay shall expose only enrollment, authenticated device connection, revocation, and health functionality. It shall keep no user payload after forwarding, shall not inspect feature payloads beyond routing/size metadata, and shall maintain only configuration, device credentials, pair mappings, and safe operational counters.

### RELAY-FR-14: Docker deployment
The repository shall include a pinned, non-root container image, Docker Compose configuration, persistent configuration volume, health check, environment template without secrets, Tailscale/private-network instructions, backup instructions for relay identity/configuration, and upgrade/rollback instructions.

### RELAY-FR-15: User-visible state
Both apps shall distinguish Direct, Relay, Reconnecting, Paused, Enrollment Required, and Error states. Errors shall be actionable without exposing credentials or internal server details.

## Non-Functional Requirements

### RELAY-NFR-01: Security minimum
- TLS 1.2 or newer for each client-to-relay connection.
- Unique revocable credentials per device.
- Constant-time credential verification using stored credential hashes.
- Deny-by-default peer routing.
- Strict input/frame/connection limits and enrollment rate limits.
- No credentials, message payloads, note contents, phone numbers, clipboard values, filenames, or meeting content in logs.
- Configurable endpoint validation; no plaintext production transport.

### RELAY-NFR-02: Delivery guarantees
Replay-safe operations shall provide at-least-once transport with idempotent application, yielding effectively-once observable results. Live-only operations provide best-effort delivery while both peers are connected.

### RELAY-NFR-03: Failover target
When direct LAN is unavailable and relay configuration is valid, relay connection should begin within 10 seconds. Loss of either transport shall use bounded exponential reconnect with jitter and no busy loop.

### RELAY-NFR-04: Resource limits
Frames, enrollment requests, concurrent connections, and transfer chunks shall have explicit bounds. User payload shall remain endpoint-local while offline. The relay shall not become an unbounded queue.

### RELAY-NFR-05: Compatibility
Relay support shall be optional and backward-compatible. Existing direct pairing, direct LAN behavior, release signing, Second Brain local access, and Syncthing usage shall continue working without relay configuration.

### RELAY-NFR-06: Testability
Tests shall cover direct-to-relay failover, reconnect/resume, restart persistence, duplicate delivery, stale cursors, note conflicts, Syncthing/relay duplicate content, interrupted files, digest failure, enrollment replay, credential revocation, unauthorized routing, frame limits, and secret-safe logs.

### RELAY-NFR-07: Property-based testing
Property tests shall cover serialization round trips, frame parsing, operation ordering, cursor monotonicity, deduplication idempotence, conflict preservation, chunk reassembly, restart/resume models, and randomized connection transitions. Failures shall shrink and report reproducible seeds.

## Out of Scope
- Replaying live call controls, screen frames, or remote gestures after either peer reconnects.
- Storing user payload on the relay while a destination is offline.
- Synchronizing Mac-local meeting audio back to the phone or retaining meeting audio on the relay. Phone-captured audio may transit to the Mac exactly as it does over the direct link.
- Replacing existing direct LAN connectivity.
- Requiring Syncthing removal.
- Brain search changes in this increment.
- Public multi-tenant relay hosting.

## Acceptance Criteria
1. With Mac and phone on separate networks but both able to reach the configured Tailscale relay, Android Bridge reaches Relay Connected and existing live protocol actions work.
2. Returning to the same LAN switches to Direct without duplicate user-visible events.
3. Creating offline replay-safe changes on either device, restarting the originating app, and reconnecting later delivers every unacknowledged delta once observably.
4. Concurrent offline edits to one note preserve both versions.
5. Meeting text and photos synchronize. Phone-captured audio can reach the Mac through relay transport, but Mac-local audio never synchronizes back to the phone; no audio names or absolute paths enter mirrored meeting content.
6. Relay restart does not lose enrollment/pair configuration and does not require payload recovery because payload remains endpoint-local.
7. Revoked or incorrect credentials cannot connect or route frames.
8. Existing direct-only users observe no behavior change.
9. Android, Swift, relay, integration, property, release-policy, and packaging validation pass.

## Extension Configuration
- **Security Baseline**: Disabled for this private relay increment by user instruction; RELAY-NFR-01 remains a mandatory project safety boundary.
- **Resiliency Baseline**: Disabled.
- **Property-Based Testing**: Full.
