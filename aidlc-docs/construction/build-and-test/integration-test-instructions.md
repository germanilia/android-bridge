# Integration Test Instructions — android_bridge

Integration here means (a) **cross-language wire interop** (automated, runs today) and (b) the
**walking-skeleton end-to-end path** across two real devices (manual, needs hardware). Resiliency
baseline is OFF (NFR-5.3), so this covers ordinary reconnect, not chaos/failover testing.

---

## 1. Cross-language vector interop (automated — runs today)
Both protocol impls decode the **same** canonical vectors so the Swift and Kotlin codecs are proven
to accept an identical on-the-wire contract.
- **Vectors:** `protocol/vectors/control-messages.jsonl` (one JSON envelope per line).
- **Kotlin:** `cd protocol/kotlin && ./gradlew test` → `InteropVectorTest` decodes every vector,
  asserts each `type` is registered and the expected set is present.
- **Swift:** `cd protocol/swift && swift test` (or `swift run ProtocolCheck`) → the "cross-language: decodes N shared
  wire vectors" check decodes the same file.
- **To extend:** add a line to the vectors file and both suites pick it up — keep the two sides in
  lockstep with `protocol/PROTOCOL.md`.

## 2. Walking-skeleton end-to-end (manual — needs two real devices)
Per decision U-Q4, the first cross-device milestone after U1–U3 is a thin path: **pair → connect →
exchange one round-trip control message visible in both UIs.** Steps:
1. Build + install the Android app (`./gradlew :app:assembleDebug`, then install the APK) and the Mac
   app (Xcode) on devices on the **same 5 GHz LAN**.
2. **Pair (U2):** show the QR on one device, scan/enter on the other; confirm both show "Paired" and
   each pinned the peer cert (trust-on-first-use).
3. **Connect (U3):** confirm mDNS discovery finds the peer and an **mTLS** link establishes; an
   unpinned third device must be **refused** (CC-SEC).
4. **Round-trip:** send a `link.hello`/`link.heartbeat` and confirm the reply is observed on both
   sides; pull the network briefly and confirm **auto-reconnect** (FR-2.4) returns to CONNECTED.
5. **Status (US-2.3):** Mac menu-bar + Android app reflect connected/reconnecting/disconnected.

## 3. Per-feature integration (manual — per device capability)
Once the skeleton is green, exercise each feature on real hardware:
- **U4 notifications** — grant notification access; post a notification on the phone; see it on the
  Mac. **U5 SMS** — grant SMS + contacts; receive a text; see it threaded on the Mac.
- **U6 files** — drag a file Mac→phone and phone→Mac; verify it lands in the configured destination
  with correct bytes (the chunk/reassemble core is already PBT-covered).
- **U7 clipboard** — copy on one device, push (default MANUAL), paste on the other.
- **U8 screen mirror** — start capture (MediaProjection consent), view on Mac, confirm the on-phone
  capture indicator and ≤ ~80 ms latency target on a healthy 5 GHz LAN (NFR-3.1).
- **U9 calls** — complete one-time Bluetooth HFP pairing; incoming call shows caller-ID on Mac;
  answer/decline/dial from Mac with **audio over Bluetooth HFP** (never over the link).
- **U10 settings/permissions** — toggle a feature off and confirm it stops; revoke one permission and
  confirm that feature degrades gracefully while others keep working (US-9.3, fail-closed).

## Status / honesty
- **Runs today:** the cross-language vector interop (section 1) — automated and passing — plus the
  in-process **mTLS handshake + pinned-peer rejection** (`TlsIntegrationTest`, Android) and the Android
  app launching on an emulator. Xcode is installed, so `swift test` and the runnable `.app` also run here.
- **Cannot run here:** the live two-device flows in sections 2–3 — they require an Android 13+ phone + a
  Mac on the same LAN, Bluetooth, telephony, and screen capture (no phone / second device on this build
  machine). Documented for a properly equipped environment.
