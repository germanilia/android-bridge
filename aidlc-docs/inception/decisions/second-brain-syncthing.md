# Decision: Second Brain sync via Syncthing (not the device link)

**Status:** Accepted
**Supersedes:** the `mobile-second-brain-sync-*` requirement/plan drafts under
`aidlc-docs/inception/` (the in-app two-minute bidirectional sync design).

## Decision

The mobile Second Brain is **no longer synced over the Android↔Mac device link**.
Instead, the Second Brain is a plain tree of Markdown files that
**[Syncthing](https://syncthing.net/)** keeps in sync across three nodes:

- the **home server** (an always-on Syncthing node),
- the **Mac** (`~/second_brain`, overridable via `BRAIN_ROOT`),
- the **Android phone** (a user-granted folder).

The Android app keeps its Second Brain **view and editor**, but now reads and
writes the local Syncthing folder directly instead of pulling/pushing over the
link.

## Why

- **Availability, not just reachability.** The Mac is a laptop — it sleeps and
  travels. Peer-to-peer sync only works when both devices are awake at once.
  Tailscale gives *reachability* off-LAN but does not make the Mac always-on.
  An always-on home-server Syncthing node lets the phone capture notes while the
  Mac is closed and have them converge later.
- **The data is just Markdown files.** Syncthing is purpose-built to sync a
  folder tree, handles conflicts, and runs over the existing Tailscale network.
  Delegating to it removed more code than it added.
- **Live sync is not required.** Eventual convergence is acceptable, so the phone
  can sync opportunistically and Android background/doze limits stop mattering.

## Code impact

- **Protocol:** removed the 9 `secondBrain.*` message types
  (`protocol/kotlin/.../Model.kt`, `protocol/swift/.../Model.swift`).
- **Mac:** removed only the phone-serving sync handlers in
  `BridgeCore/LinkManager.swift`. The Mac's own Second Brain (browse/edit/map/Q&A)
  and the meeting→brain export (`SecondBrainExporter`) are unchanged — Syncthing
  distributes `~/second_brain`.
- **Android:** replaced `SecondBrainCache` (JSON cache filled over the wire) with
  `SecondBrainFolder` — a Storage Access Framework (`DocumentFile`) store backed by
  a user-granted tree URI. The Brain tab and editor stay; the wire-sync plumbing
  (router registrations, `secondBrainLoop`, pending-op queue) is gone.

## Home-server Syncthing setup

1. Install Syncthing on the **home server** (keep it running as a service), the
   **Mac**, and the **Android** phone. All three are already on the Tailscale
   tailnet.
2. On the Mac, add `~/second_brain` (or your `BRAIN_ROOT`) as a Syncthing folder.
3. Share that folder with the home server, and share it from the home server to
   the phone. The home server is the always-on node, so the phone and Mac never
   need to be online at the same time.
4. On the phone, let Syncthing sync the folder to a location the app can be
   granted access to, then open the app's **Brain** tab and pick that folder with
   **Choose Syncthing folder** (a one-time SAF grant).
5. **Lock the tailnet ACL** so only the phone, Mac, and home server can reach each
   other — the tailnet is the access boundary for this data.
