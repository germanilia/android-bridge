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

## 4. Meeting completion + Calendar enrichment (manual — Mac)

1. Add the Google account to macOS **System Settings → Internet Accounts** and confirm its events appear in Apple Calendar.
2. Start and stop a short Mac meeting; verify Stop clears recording state immediately and the app remains navigable while the meeting shows `Finalizing`.
3. Grant Calendar access when macOS asks; verify no Android Bridge customer/Second Brain completion popup appears.
4. With one overlapping timed event, verify its title/calendar snapshot is attached and one unambiguous external company domain becomes the customer suggestion.
5. Create two overlapping timed events, finish another recording, and verify `Choose calendar event` lists both plus `Enter manually` and `No calendar event`.
6. Deny Calendar access for one run; verify the meeting remains ready, retained media is usable, and Calendar Settings/Retry remain available.
7. Invoke Second Brain explicitly; verify nothing is filed before that action and repeated transfer updates rather than duplicates the note.

## Status / honesty
- **Runs today:** the cross-language vector interop (section 1) — automated and passing — plus the
  in-process **mTLS handshake + pinned-peer rejection** (`TlsIntegrationTest`, Android) and the Android
  app launching on an emulator. Xcode is installed, so `swift test` and the runnable `.app` also run here.
- **Cannot run here:** the live two-device flows in sections 2–3 — they require an Android 13+ phone + a
  Mac on the same LAN, Bluetooth, telephony, and screen capture (no phone / second device on this build
  machine). Documented for a properly equipped environment.

## 5. Clipboard and Second Brain reliability verification

Run after the Android phone connects:

1. Install `android/app/build/outputs/apk/debug/app-debug.apk` with `adb install -r` and launch Android Bridge.
2. Leave Auto Sync off on both devices. Copy new text on each device and confirm nothing sends until Push Clipboard is selected.
3. Enable Auto Sync on Mac, copy text, and confirm Android receives a private notification. Select Copy and paste the exact text on Android. Confirm no echo event returns to Mac.
4. Enable Auto Sync on Android, keep Android Bridge foregrounded, copy text, and confirm the Mac pasteboard updates. Background the app and confirm the UI accurately avoids promising background clipboard observation.
5. Inspect both activity lists and confirm copied text never appears.
6. Keep both Brain tabs open. Create one Markdown note on Mac and one on Android. Confirm each local app updates within three seconds and Syncthing later converges the files through the home server.
7. Start editing a note without saving, change its file from the other device, and confirm the unsaved draft is not overwritten.
8. Remove folder permission or choose an unavailable root temporarily and confirm each app reports an actionable failure instead of Saved or a stale success state.

## 6. Meeting customer automation verification

1. Open Settings and choose a Main calendar. Relaunch and confirm the selection persists.
2. Edit a meeting customer. Type part of an existing name, open the dropdown, and select the filtered customer.
3. Type a unique new name, select Create, save, then edit another meeting and confirm the new customer appears.
4. Refresh Calendar Match on a recording that started or ended within 15 minutes of one preferred-calendar event. Confirm that event auto-selects.
5. Use an event with no exact customer match. Confirm the customer picker opens, select or create a customer, then refresh a later matching event and confirm it auto-selects the remembered customer.
6. Create two qualifying events. Confirm the app shows the event picker instead of guessing.
7. In Settings, change one learned match and verify the next matching event uses the replacement. Forget it and verify the next match asks again.
8. Confirm customer names, participant addresses, event titles, URLs, and learned signals do not appear in Activity or `/tmp/androidbridge-diag.txt`.

## 7. Direct distribution and trusted updates

1. Inspect the stable Release and require the versioned DMG/APK, predictable aliases, checksums, two CycloneDX SBOMs, manifest, and release notes.
2. On a clean Apple Silicon Mac, download the DMG alias, mount it, drag the app to Applications, Control-click then Open, and confirm normal setup without disabling Gatekeeper.
3. On Android 13+, install the stable APK after unknown-source consent. Publish a later same-key version and confirm it upgrades without uninstalling or losing data.
4. Confirm both apps discover the later stable version without blocking startup and require consent before artifact download.
5. Modify fixture bytes and confirm Mac never opens the DMG and Android never invokes the installer.
6. Confirm Android rejects a differently signed APK and removes it.
7. Cancel each download and confirm partial updater-owned files are removed while installed apps and user data remain.
8. Exercise `latest-build` replacement and verify a failed staged promotion leaves the prior complete rolling Release available.
