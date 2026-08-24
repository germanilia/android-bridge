# In-App Sync Relay Execution Plan

## Decision
Proceed autonomously using the user's completed answers and instruction to ask no further questions. Direct LAN remains preferred; the relay is an optional private Tailscale fallback. Offline payloads stay on endpoints and resume through durable deltas after both peers reconnect.

## Inception
- [x] Workspace Detection — brownfield Kotlin/Swift monorepo; current direct transport and Syncthing paths inspected.
- [x] Reverse Engineering — skipped because current architecture and implementation records are sufficient.
- [x] Requirements Analysis — comprehensive requirements recorded in `aidlc-docs/inception/requirements/in-app-sync-relay-requirements.md`.
- [x] User Stories — skipped; requirements and acceptance criteria directly define the single-owner workflows.
- [x] Workflow Planning — this plan.
- [x] Application Design — relay, enrollment, session, durable operation, conflict, and transport-selection components defined.
- [x] Units Generation — RELAY1 through RELAY5 and dependencies finalized.

## Construction Units

### RELAY1 — Protocol and Durable Sync Core
- [ ] Define typed relay handshake, enrollment, operation, acknowledgement, cursor, note-delta, and transfer-chunk models in Kotlin and Swift.
- [ ] Add endpoint-local durable outbox/inbox journals with atomic persistence, idempotent apply, monotonic cursors, and owned transfer spool.
- [ ] Add example and property tests for serialization, ordering, deduplication, conflict preservation, chunking, and restart/resume.

### RELAY2 — Stateless Home-Server Relay
- [ ] Implement the smallest standalone relay with enrollment, unique credential hashing, pair authorization, live bidirectional frame routing, revocation, rate/frame/connection limits, and safe structured logs.
- [ ] Ensure the relay stores no user payload and fails closed.
- [ ] Add unit, integration, misuse, restart, and property tests.
- [ ] Add pinned non-root container, Docker Compose, health check, environment template, and Tailscale deployment documentation.

### RELAY3 — Android Client Integration
- [ ] Add encrypted relay settings and enrollment UI.
- [ ] Add direct-first transport selection and automatic relay fallback.
- [ ] Integrate the same router with relay sessions.
- [ ] Persist replay-safe outbound deltas, resume from peer acknowledgements, preserve Brain conflicts, and spool files/meeting photos.
- [ ] Exclude audio and classify live-only messages explicitly.
- [ ] Add Android unit/integration/property tests and device diagnostics.

### RELAY4 — macOS Client Integration
- [ ] Add Keychain-backed relay settings and enrollment UI.
- [ ] Add direct-first transport selection and automatic relay fallback.
- [ ] Integrate the same router with relay sessions.
- [ ] Persist replay-safe outbound deltas, resume from peer acknowledgements, preserve Brain conflicts, and spool files/meeting photos.
- [ ] Exclude audio and classify live-only messages explicitly.
- [ ] Add Swift unit/integration/property tests and safe diagnostics.

### RELAY5 — End-to-End Validation and Deployment
- [ ] Validate direct-to-relay and relay-to-direct switching without duplicates.
- [ ] Validate offline changes, app restarts, reconnect resume, conflicts, files/photos, relay restart, revocation, and malformed traffic.
- [ ] Run complete Android, Swift, relay, release-policy, signing, SBOM, scanner, and packaging checks.
- [ ] Deploy relay to the private home server and test phone/Mac across separate networks.
- [ ] Install signed local apps, preserve data, publish the next version, and verify stable downloads.

## Stage Selection
- Functional Design: execute for RELAY1–RELAY4 because delivery semantics and conflict rules are stateful.
- NFR Requirements: execute for all units because security, performance, availability, and resource limits matter.
- NFR Design: execute for RELAY1–RELAY4.
- Infrastructure Design: execute for RELAY2 and RELAY5 because a self-hosted container and Tailscale routing are required.
- Code Generation: execute for every unit.
- Build and Test: execute after all units.

## Security Boundary
Even though the full Security Baseline extension is disabled for this private deployment, implementation is blocked unless TLS, unique revocable credentials, deny-by-default routing, secret-safe logs, strict input limits, owned persistence paths, and fail-closed behavior are present.

## Extension Compliance
- Security Baseline: disabled for this increment; minimum project safety boundary above remains mandatory.
- Resiliency Baseline: disabled.
- Property-Based Testing: full; applicable properties are mandatory in design, code, and CI.
