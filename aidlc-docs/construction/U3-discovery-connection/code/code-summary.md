# Code Summary — U3 Discovery & Connection

**Status: mTLS transport implemented + integration-tested in-process; NSD/live-LAN still device-only (◐).**
The connection state machine and message router are implemented in both languages and unit-tested. A
**real mutual-TLS transport** now exists (Kotlin) and is verified by an in-process localhost integration
test — handshake succeeds between mutually-pinned peers and an unpinned peer is rejected. NSD discovery and
the live cross-device link still require real hardware (no second device / real LAN here).

## What exists
- **Pure, tested (Kotlin)** — `core/ConnectionState.kt` (`ConnectionStateMachine`: discovery→connecting→
  connected, drop→reconnecting; FR-2.3/2.4); `core/MessageRouter.kt` (register/route, fail-closed drop of
  invalid + unrouted, SECURITY-15); `core/LinkLogger.kt` (no-PII filter, SECURITY-03).
- **Pure, tested (Swift)** — equivalents in `mac/Sources/BridgeCore/Core.swift`.
- **Real mTLS transport (Kotlin, integration-tested)** — `core/CertFactory.kt` (BouncyCastle self-signed
  EC P-256 X.509 + SHA-256 fingerprint) and `core/TlsConnection.kt` (`TlsLink`: pinned mutual-TLS server +
  client via `SSLContext`/`SSLServerSocket`, `needClientAuth`, a `PinnedTrustManager` that rejects any
  non-pinned peer cert, and a `Session` that reads/writes length-prefixed protocol messages).
- **Android wrappers (compiled, device-only)** — `android/NsdDiscovery.kt` (`NsdManager` mDNS browse/
  resolve → `onPeerFound`), `android/LinkForegroundService.kt` (foreground service + ongoing notification, FR-2.2).

## Tests (passing)
- Kotlin `MessageRouterTest` (route valid / drop unrouted / drop version-mismatch), `ConnectionStateMachineTest`.
- **`TlsIntegrationTest`** — in-process localhost mTLS: two mutually-pinned peers complete the handshake and
  exchange `link.hello`→`link.heartbeat`; an unpinned peer is rejected at the handshake (CC-SEC / SECURITY-06/-08).
  Run: `./gradlew :app:testDebugUnitTest` ✅ (24 tests total)
- Swift `MacCheck` + `swift test` router/state checks. ✅

## Not yet implemented / not verified
- NSD **advertise** side (only browse exists); control/stream multiplexing, heartbeat, and auto-reconnect
  wiring on top of `TlsLink`; the Swift `NWBrowser`/`NWConnection` transport.
- Discovery + the live cross-device mTLS link require real hardware — **not verified across two physical
  devices**. The walking-skeleton (pair + connect + one round-trip) is a manual two-device step; its TLS
  core is already proven in-process by `TlsIntegrationTest`.

**Verification: ✅ router + state machine + in-process mTLS handshake/pinning green; live two-device link not hw-verified.**
