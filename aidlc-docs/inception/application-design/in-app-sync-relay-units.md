# In-App Sync Relay Units

## RELAY1 — Protocol and Durable Sync Core
**Owns:** shared model additions, codecs, replay classification, durable operation semantics, hash/conflict rules, Kotlin/Swift golden vectors, and PBT.

**Depends on:** existing protocol v1.

**Produces:** reusable types and deterministic behavior consumed by both apps and relay integration.

## RELAY2 — Stateless Home-Server Relay
**Owns:** Ktor service, enrollment, invitation, credential rotation/revocation, authenticated WSS routing, health, safe logging, limits, container, Compose, and deployment files.

**Depends on:** RELAY1 relay envelope and validation contract.

**Produces:** private self-hosted routing service with no user-payload queue.

## RELAY3 — Android Relay and Sync Client
**Owns:** OkHttp WSS transport, encrypted settings, direct-first selector, durable journal/spool, resume/ACK, Brain compare-and-set/conflicts, meeting/file transfer persistence, foreground lifecycle, UI, tests.

**Depends on:** RELAY1. Integrates against RELAY2 after both are testable.

## RELAY4 — macOS Relay and Sync Client
**Owns:** native WSS transport, Keychain settings, direct-first selector, durable journal/spool, resume/ACK, Brain compare-and-set/conflicts, meeting/photo projection, sleep/wake behavior, UI, tests.

**Depends on:** RELAY1. Integrates against RELAY2 after both are testable.

## RELAY5 — End-to-End Validation and Release
**Owns:** cross-network integration, fault injection, payload-log canaries, container/reverse-proxy checks, client installation, release artifacts, SBOM/scanning, documentation, and publication.

**Depends on:** RELAY1, RELAY2, RELAY3, and RELAY4.

## Dependency Order
1. RELAY1 establishes the compatibility and persistence contract.
2. RELAY2 can proceed once relay envelopes are stable.
3. RELAY3 and RELAY4 can proceed in parallel after RELAY1.
4. RELAY5 begins after all implementation units pass their local suites.

## Scope Guard
A relay UI shall remain disabled in release builds until RELAY1 durable persistence, idempotent handling, conflict preservation, and transport frame bounds are complete. A partial implementation must not expose a path that can silently lose offline data.
