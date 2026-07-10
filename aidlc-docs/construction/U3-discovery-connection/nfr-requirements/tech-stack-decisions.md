# Tech Stack Decisions — U3 Discovery & Connection

| Concern | Decision | Rationale |
|---------|----------|-----------|
| **Languages** | Kotlin (`android/app/.../core/` + `.../android/`) + Swift (`mac/`, not yet written) | Native per app; pure pieces (state machine, chunker) shared in shape + JVM-testable. |
| **Discovery** | mDNS/Bonjour — Android **`NsdManager`**, Mac **`NWBrowser`/`NWListener`** | Zero-config LAN peer discovery; generic public APIs (AR4 / NFR-6.1). Service type `_androidbridge._tcp.`. |
| **Transport security** | **Mutual TLS (1.2+)** against U2-pinned certs | Encrypts in transit + authenticates both ends; rejects unpinned (SECURITY-01/-06/-08). |
| **Session model** | **Single mTLS session, multiplexed** control + binary streams (AR1) | Simplest trust boundary; one socket carries everything. |
| **TLS stack** | Android: JSSE `SSLSocket` + custom `X509TrustManager` (pin check); Mac: `Network.framework` (`NWConnection` + `sec_protocol`) | Platform-native TLS; pinning via the trust callback. |
| **Background link (Android)** | **Foreground service** (`connectedDevice` type) + ongoing notification | Keeps link alive when backgrounded (FR-2.2). |
| **Reconnect** | Ordinary retry/backoff driven by the pure `ConnectionStateMachine` | Resiliency baseline NOT applied (NFR-5.3); local link. |
| **PBT framework (PBT-09)** | Kotlin → **Kotest Property Testing**; Swift → seeded `PropertyHarness` (see deviation) | For chunker round-trip + state-machine/chunking invariants. |
| **Dependency pinning (SECURITY-10)** | Gradle version catalog + lockfile; SPM `Package.resolved` | Exact versions; scan + SBOM at Build & Test. |

## Environment deviation (no Xcode on this machine)
Only **Swift Command Line Tools** are present — **XCTest and SwiftCheck are unavailable**, and the
Mac `Network.framework`/Keychain transport cannot be built or run here at all. The pure, portable
pieces (state machine, stream chunker) are tested in Swift via the dependency-free seeded
`PropertyHarness` (`protocol/swift/.../PropertyHarness.swift` pattern), meeting **PBT-09 intent**
(generators + shrinking-lite + seeded reproducibility). On a machine with Xcode you would swap to
**SwiftCheck + XCTest** and build the macOS transport unchanged. Kotlin/JVM uses **Kotest** normally;
`NsdManager`/`SSLSocket`/foreground service require an Android device/emulator.

## Notes
- Pure transport logic (`ConnectionStateMachine`, `StreamChunker`/`StreamReassembler`) has **no**
  third-party dependency. mTLS uses platform TLS; mDNS uses platform discovery.
- The actual `ConnectionManager` (TLS handshake + multiplexing + heartbeat wiring) is the main
  remaining transport piece to generate on both platforms.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
