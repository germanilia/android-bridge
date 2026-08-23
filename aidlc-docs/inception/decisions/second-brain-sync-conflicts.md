# Decision: Second Brain sync conflicts — remote wins

**Status:** Accepted

## Problem

Syncthing occasionally produces conflict copies on the phone
(`note.sync-conflict-YYYYMMDD-HHMMSS-DEVICE.md`) when the same note changed on
two nodes before syncing. They cluttered the Android Brain tab and the user has
no interest in manual merging — the remote (Mac/home-server) version should win.

## Decision

1. **In the app:** conflict copies are hidden from the note tree and search.
   The drawer shows a "N sync conflict copies" banner with a **Keep synced**
   action that deletes every conflict copy, accepting the winner file Syncthing
   already picked (`SecondBrainFolder.deleteConflicts`).
2. **In Syncthing (one-time, on the phone):** stop conflict copies from being
   created at all. In the Syncthing app on the phone open the shared folder →
   **Edit → Advanced (folder settings)** and set **Maximum conflicts /
   `maxConflicts` to `0`**. From then on the newer version simply wins with no
   conflict file left behind.

## Why not "receive only" on the phone?

A receive-only folder would make the remote win unconditionally, but it would
also block the notes the app itself creates/edits on the phone (`mobile/…`)
from ever reaching the Mac. `maxConflicts = 0` keeps two-way editing and just
drops the conflict-copy litter; the app's cleanup action handles copies that
already exist (or arrive from other nodes).
