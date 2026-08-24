# In-App Sync Relay Code Generation Plan

## RELAY1 — Protocol and Durable Sync Core
- [x] Add failing Kotlin and Swift model/codec tests for capabilities, resume, acknowledgements, immutable sync operations, conflict outcomes, and transfer chunks.
- [x] Add failing PBT for round trips, malformed frames, cursor monotonicity, deduplication, resume suffixes, conflict preservation, and chunk reassembly.
- [x] Implement additive protocol models and registry entries in both languages.
- [x] Add frame-size enforcement before allocation on Android and bounded receive buffering on macOS.
- [x] Implement Kotlin and Swift durable journal models with atomic persistence and content-addressed owned blobs.
- [x] Make all RELAY1 tests pass and mark each completed checkbox immediately.

## RELAY2 — Stateless Home-Server Relay
- [x] Add relay Gradle module and pinned Ktor/Kotest dependencies.
- [x] Add failing HTTP/WSS integration tests for setup-code enrollment, invitation enrollment, credential hashing, revocation, pair isolation, absent peers, frame limits, backpressure, and secret-safe logs.
- [x] Add relay PBT for envelope parsing, duplicate connection replacement, random connect/disconnect schedules, and byte-exact forwarding.
- [x] Implement enrollment/config persistence without user-payload persistence.
- [x] Implement authenticated WSS routing and health endpoints.
- [x] Add pinned non-root container, Compose, health check, environment template, deployment metadata, and deploy script.
- [x] Make all RELAY2 tests pass and validate the container locally.

## RELAY3 — Android Client
- [x] Add failing tests for relay settings validation, credential persistence boundary, transport selection, stale-session rejection, reconnect, replay classification, durable send/ACK, note conflict preservation, and transfer spool recovery.
- [x] Add OkHttp WSS transport and relay enrollment client.
- [x] Add encrypted relay settings and Compose controls/status.
- [x] Integrate direct-first relay fallback into `LinkManager` with one active session generation.
- [x] Add app-private durable journal and blob spool.
- [x] Integrate replay-safe messages, note snapshots, files, meeting photos, and phone-origin meeting audio; keep live-only actions non-replayable.
- [ ] Make Android tests/build/lint-vital pass.

## RELAY4 — macOS Client
- [x] Add failing tests for URL validation, Keychain boundary, transport selection, stale-session rejection, sleep/wake, replay classification, durable send/ACK, note conflict preservation, and transfer spool recovery.
- [x] Add native WSS transport and enrollment client.
- [x] Add Keychain-backed relay settings and SwiftUI controls/status.
- [x] Integrate direct-first relay fallback into `LinkManager` with one active session generation.
- [x] Add Application Support durable journal and blob spool.
- [x] Integrate replay-safe messages, note snapshots, files, meeting text/photos, and phone-origin meeting audio receipt; keep Mac audio local and live actions non-replayable.
- [x] Make Swift tests/build/app assembly pass.

## RELAY5 — Integration and Release
- [ ] Run relay plus simulated clients across WSS and inject disconnects/restarts.
- [ ] Verify offline restart/resume, duplicate suppression, conflicts, files, meetings, credentials, limits, and payload canaries.
- [x] Build and validate the homeserver image and deployment bundle without auto-deploying it.
- [ ] Run complete Android, Swift, protocol, release-policy, signing, SBOM, scanner, and packaging suites.
- [ ] Install local signed apps and test direct/relay behavior on separate networks.
- [ ] Complete evidence, commit, push, CI, versioned release, and stable-download verification.

## Release Gate
Do not expose relay enablement in a public build until durable persistence, idempotent replay, frame bounds, conflict preservation, credential revocation, and direct-only compatibility pass. Partial relay code must stay disabled.
