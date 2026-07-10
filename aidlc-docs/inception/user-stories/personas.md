# Personas — android_bridge

## P1 — Owner-User ("Ilia") · PRIMARY
The person the product is built for: owns the hardware, uses both devices all day, cares about privacy and polish.

- **Devices**: Samsung Galaxy (Android 16) + Apple Silicon Mac (M1).
- **Technical level**: High — comfortable granting permissions, scanning QR codes, doing a one-time Bluetooth setup.
- **Goals**:
  - Stay in the Mac flow without picking up the phone for notifications, texts, files.
  - See and handle calls from the desk.
  - Move files and clipboard between devices instantly.
  - Keep everything **local and private** — no cloud, no leaks.
- **Frustrations**:
  - Existing tools are fragmented (separate apps for mirroring, files, messages) and not Mac-native.
  - Cloud relays and accounts for something that should be peer-to-peer.
- **Success looks like**: pair once, then continuity "just works" with native Mac polish.
- **Maps to**: nearly all stories (US-1.x through US-9.x).

## P2 — Open-Source Contributor ("Dev") · SECONDARY
A developer who discovers the open-sourced repo and wants to run, understand, extend, or port it.

- **Devices**: Some other Android phone (not necessarily Samsung) + a Mac.
- **Technical level**: High — reads the protocol docs, builds from source, writes tests.
- **Goals**:
  - Build and run both apps from a clean checkout.
  - Understand the device-link protocol and add a feature without reworking transport.
  - Run it on **generic Android** (no Samsung lock-in).
  - Trust the test suite (incl. protocol round-trip property tests) to catch regressions.
- **Frustrations**:
  - Tightly-coupled code, undocumented wire formats, vendor-specific APIs that don't port.
- **Success looks like**: clear module boundaries, a documented protocol, green tests, runs on any Android 13+ device.
- **Maps to**: US-10.x (maintainability/portability) plus the security/testing acceptance criteria attached across all stories.

---

## Persona → Story Map (summary)
| Persona | Primary stories |
|---|---|
| P1 Owner-User | US-1.x, US-2.x, US-3.x, US-4.x, US-5.x, US-6.x, US-7.x, US-8.x, US-9.x |
| P2 Contributor | US-10.1, US-10.2, US-10.3; cross-cutting ACs (security/privacy, PBT) on all stories |
