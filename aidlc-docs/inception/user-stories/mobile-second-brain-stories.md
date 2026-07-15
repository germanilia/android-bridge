# Mobile Second Brain User Stories

## Persona Mapping

All stories target **P1 — Owner-User**.

## Epic 1 — Android Browse and Read

### MSB-US-1 — Browse Second Brain Tree `[Increment 8]`
As the Owner-User, I want a Second Brain screen on Android so I can browse my Markdown node tree from my phone.

**Acceptance Criteria**
- Given the Android app has synced with the Mac, when I open the Second Brain screen, then I see folders and Markdown nodes.
- Given the app is offline, when I open the Second Brain screen, then I see the cached tree.
- Given sync has never completed, when I open the screen, then I see a safe empty/loading state with sync guidance.

### MSB-US-2 — Read Markdown Node `[Increment 8]`
As the Owner-User, I want to open a Markdown node on Android so I can read my Second Brain content away from the Mac.

**Acceptance Criteria**
- Given a cached Markdown node exists, when I tap it, then Android shows readable content.
- Given the node was updated on Mac and synced, when I open it, then I see the updated content.
- Given a node cannot be loaded, when I open it, then Android shows a safe error without exposing internal paths or stack traces.

## Epic 2 — Android CRUD

### MSB-US-3 — Create Markdown Node `[Increment 8]`
As the Owner-User, I want to create a Markdown node on Android so new thoughts can be captured immediately.

**Acceptance Criteria**
- Given I enter a valid Markdown node title/path and content, when I save, then the node appears locally and is queued for Mac sync.
- Given Android is connected to Mac, when I save, then the change is sent through the secure paired channel to the Mac skill boundary.
- Given the path is invalid or non-Markdown, when I save, then the operation is rejected with a clear safe error.

### MSB-US-4 — Edit Markdown Node `[Increment 8]`
As the Owner-User, I want to edit an existing Markdown node on Android so I can update notes from my phone.

**Acceptance Criteria**
- Given a Markdown node is cached, when I edit and save it, then the local cache updates and a pending update is queued.
- Given Android is offline, when I save, then the app reports a pending change rather than failing the edit.
- Given the same acknowledged operation is replayed, when sync retries, then the note is not duplicated or corrupted.

### MSB-US-5 — Delete Markdown Node `[Increment 8]`
As the Owner-User, I want to delete a Markdown node on Android so I can clean up my Second Brain from the phone.

**Acceptance Criteria**
- Given a cached Markdown node exists, when I delete it and confirm, then it disappears locally and a pending delete is queued.
- Given Android reconnects, when pending deletes replay, then Mac deletes the node through the skill boundary.
- Given delete fails on Mac, when the result returns, then Android keeps enough state to retry or surface failure without corrupting the tree.

## Epic 3 — Offline Cache and Queue

### MSB-US-6 — Use Full Offline Cache `[Increment 8]`
As the Owner-User, I want the full Markdown Second Brain cached on Android so I can read and work offline.

**Acceptance Criteria**
- Given at least one sync completed, when Android is disconnected, then I can browse, read, search, create, edit, and delete Markdown nodes locally.
- Given the app restarts, when I reopen it, then cached nodes and pending changes remain available.
- Given local storage has queued changes, when the UI loads, then pending-change count is visible.

### MSB-US-7 — Replay Pending Changes on Reconnect `[Increment 8]`
As the Owner-User, I want offline edits to sync automatically when the Mac connection returns so I do not have to remember manual steps.

**Acceptance Criteria**
- Given Android has pending changes and the Mac reconnects, when secure connection is established, then Android automatically pushes queued changes.
- Given replay succeeds, when acknowledgements return, then pending-change count decreases.
- Given replay partially fails, when sync completes, then failed changes remain queued for retry.

## Epic 4 — Sync Control and Status

### MSB-US-8 — Periodic Bidirectional Sync and Sync Now `[Increment 8]`
As the Owner-User, I want automatic two-minute sync and a Sync Now button so my phone and Mac stay current.

**Acceptance Criteria**
- Given Android and Mac are connected, when two minutes pass, then bidirectional sync runs.
- Given I tap Sync Now while connected, then sync starts immediately.
- Given sync is running, when I view the Second Brain screen, then I see syncing/last-success status.

### MSB-US-9 — Understand Sync Failures Safely `[Increment 8]`
As the Owner-User, I want clear sync feedback so I can tell whether my notes are safe.

**Acceptance Criteria**
- Given sync fails, when the UI updates, then I see a safe reason and pending-change count.
- Given logs are produced, when debugging, then logs do not include note bodies or secrets.
- Given an invalid message arrives, when validation fails, then the operation is rejected and no local data is applied.

## Epic 5 — Search and Conflict Behavior

### MSB-US-10 — Search Local Markdown Cache `[Increment 8]`
As the Owner-User, I want local title and content search on Android so I can find notes without the Mac.

**Acceptance Criteria**
- Given Markdown nodes are cached, when I search a word in a title or body, then matching nodes appear.
- Given Android is offline, when I search, then results still come from local cache.
- Given results are shown, then each result includes node title/path and a short snippet.

### MSB-US-11 — Predict Conflict Resolution `[Increment 8]`
As the Owner-User, I want conflicts resolved predictably so disconnected edits do not surprise me.

**Acceptance Criteria**
- Given Mac and Android both changed a node while disconnected, when sync compares versions, then last-write-wins using timestamps.
- Given two versions have identical timestamps or clock skew risk, when design handles tie-break, then the result is deterministic.
- Given a version loses, when sync logs the event, then it records path/timestamps/source but not note content.

## Cross-Cutting Acceptance Notes

- All Second Brain operations require existing paired mutual-TLS channel.
- Mac skill/CLI remains the only filesystem reader/writer.
- Markdown-only scope enforced in UI and protocol validation.
- PBT required for protocol round trips, queue replay/idempotency, conflict model, path normalization, and sync state machine/model behavior.
- Example tests required for create/edit/delete/offline/reconnect/conflict scenarios.

## INVEST Check

- **Independent**: Stories split by user-visible capability.
- **Negotiable**: Implementation details remain in design/code stages.
- **Valuable**: Each story gives direct personal workflow value.
- **Estimable**: Each story maps to bounded UI/sync behavior.
- **Small**: Stories avoid bundling entire feature except cross-cutting notes.
- **Testable**: Each story has Given/When/Then criteria.
