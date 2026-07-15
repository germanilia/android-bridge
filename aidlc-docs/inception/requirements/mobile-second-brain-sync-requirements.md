# Requirements — Mobile Second Brain Sync

## Intent Analysis

- **User request**: Android app should browse, view, create, edit, and delete Second Brain nodes. It should sync with the Mac whenever connected, run bidirectional sync every 2 minutes, support a Sync Now button, queue pending Android changes while disconnected, and replay them automatically when the Mac connection returns. Mac remains the authority for filesystem access by using the existing Second Brain skill integration.
- **Request type**: New feature increment on existing Android/Mac continuity app.
- **Scope estimate**: Cross-component: Android UI and local store, shared protocol messages, Mac LinkManager/SecondBrainStore integration, sync scheduler, conflict handling, tests.
- **Complexity estimate**: Complex: offline-first editing, bidirectional sync, durable queue, conflict resolution, secure device-link transport, and Mac skill boundary.
- **Requirements depth**: Comprehensive.

## Decisions Locked

| Area | Decision |
|---|---|
| Android capabilities | Browse, view, create, edit, and delete Second Brain nodes. |
| Node format | Markdown only (`.md`). |
| Offline storage | Full Second Brain tree and all supported node contents stored on Android. |
| Sync cadence | Bidirectional sync every 2 minutes while connected, plus Sync Now button. |
| Reconnect behavior | Android automatically pushes all queued pending local changes when connection is restored. |
| Conflict policy | Last-write-wins using device timestamps. |
| Mac filesystem boundary | Mac Second Brain skill remains the only filesystem reader/writer; Android sends operations through Mac. |
| Android search | Local title/filename and content search over synced Markdown nodes. |
| Transport security | Existing paired-device secure channel only; no insecure local mode. |
| Android UI | New Second Brain tab/screen. |
| Usage model | Personal/home-use app, not SaaS or consumer service. |
| Security extension | Enabled for this increment. |
| Resiliency extension | Enabled with local/personal-use interpretations. |
| PBT extension | Enabled fully for this increment. |

## Functional Requirements

### MSB-FR-1 — Android Second Brain Browser
- MSB-FR-1.1: Android app provides a dedicated **Second Brain** tab/screen.
- MSB-FR-1.2: Android displays the full synced node tree with folders and Markdown nodes.
- MSB-FR-1.3: Android opens a selected Markdown node and renders readable content.
- MSB-FR-1.4: Android clearly shows sync state: connected, syncing, offline, pending changes, last successful sync time.

### MSB-FR-2 — Android CRUD
- MSB-FR-2.1: Android can create a new Markdown node.
- MSB-FR-2.2: Android can edit existing Markdown node content.
- MSB-FR-2.3: Android can delete a Markdown node.
- MSB-FR-2.4: Android writes all local changes first to its local store and durable pending-change queue.
- MSB-FR-2.5: CRUD operations are rejected for non-Markdown files in this increment.

### MSB-FR-3 — Full Offline Cache
- MSB-FR-3.1: Android stores the full Second Brain tree and all Markdown node contents for offline access.
- MSB-FR-3.2: Android can browse, read, search, create, edit, and delete cached Markdown nodes while disconnected.
- MSB-FR-3.3: Offline-created, edited, and deleted nodes are accumulated as pending changes until Mac reconnects.
- MSB-FR-3.4: Pending changes survive Android process death and device restart.

### MSB-FR-4 — Sync Loop
- MSB-FR-4.1: When connected to the Mac, sync runs bidirectionally every 2 minutes.
- MSB-FR-4.2: Android has a **Sync Now** action that triggers immediate bidirectional sync when connected.
- MSB-FR-4.3: On reconnect, Android automatically pushes all queued pending local changes before or during the next sync cycle.
- MSB-FR-4.4: Sync pulls Mac-side changes into Android and updates the local tree/content cache.
- MSB-FR-4.5: Sync is idempotent: replaying the same acknowledged change does not duplicate nodes or corrupt content.

### MSB-FR-5 — Mac Skill Boundary
- MSB-FR-5.1: The Mac app remains the only side that reads and writes the real Second Brain filesystem.
- MSB-FR-5.2: Android requests tree, read, create, edit, delete, and sync operations through the secure app protocol.
- MSB-FR-5.3: Mac fulfills those operations through the existing Second Brain skill/CLI wrapper.
- MSB-FR-5.4: Mac returns operation results, updated metadata, and errors to Android.

### MSB-FR-6 — Conflict Handling
- MSB-FR-6.1: Each node version carries a last-modified timestamp and device/source metadata.
- MSB-FR-6.2: If both Mac and Android changed the same node while disconnected, last-write-wins by timestamp.
- MSB-FR-6.3: The losing version is not silently discarded if feasible; the sync log records the overwritten node path, timestamps, and source device without logging content.
- MSB-FR-6.4: Clock skew handling is documented in design; if exact trust in wall-clock time is unsafe, design must add a deterministic tie-breaker.

### MSB-FR-7 — Local Search on Android
- MSB-FR-7.1: Android search covers node titles/filenames and Markdown content in the local synced cache.
- MSB-FR-7.2: Search works offline.
- MSB-FR-7.3: Search results show node title/path and a short content match snippet.

### MSB-FR-8 — Sync Status and Error Feedback
- MSB-FR-8.1: Android surfaces pending-change count.
- MSB-FR-8.2: Android surfaces last sync success/failure.
- MSB-FR-8.3: Operation failures use safe user-facing messages and keep pending changes queued for retry when appropriate.
- MSB-FR-8.4: Mac surfaces enough sync state for debugging personal use: connected device, last sync, failed operation count.

## Non-Functional Requirements

### MSB-NFR-1 — Privacy and Data Locality
- The feature is local-first and personal-use only.
- Second Brain content stays on the paired Mac and Android device.
- No cloud, account, telemetry, or third-party service is introduced by this increment.

### MSB-NFR-2 — Security Baseline Compliance
- **SECURITY-01**: All sync traffic uses existing mutual-TLS paired secure channel. Android cache and pending-change queue containing node content must use encrypted app storage or platform-protected storage appropriate for sensitive local data.
- **SECURITY-03**: Structured logs must not include node content, secrets, full note bodies, or sensitive personal data. Log paths/titles only when needed for debugging.
- **SECURITY-05**: Every Second Brain protocol message validates type, path, size, operation, timestamp, and payload bounds before processing.
- **SECURITY-08**: Only paired authenticated devices can invoke Second Brain operations. Feature-level authorization must respect the Second Brain feature toggle/permission.
- **SECURITY-09**: Safe errors only; no stack traces or internal paths in user-facing Android messages.
- **SECURITY-10**: Use existing pinned Gradle/SwiftPM dependencies and CI scanning conventions.
- **SECURITY-12**: No hardcoded secrets. Pairing credentials remain in Keychain/Keystore.
- **SECURITY-13**: Wire messages use safe schema decoding only; no unsafe deserialization.
- **SECURITY-14**: Failed auth/validation and repeated sync failures are locally logged without content.
- **SECURITY-15**: Fail closed on auth/validation errors; invalid sync operations are rejected and not applied.
- **N/A**: SECURITY-02, SECURITY-04, SECURITY-07, cloud-IAM portions of SECURITY-06, and cloud alerting portions of SECURITY-14 are not applicable because this is a local peer-to-peer app with no web/cloud tier.

### MSB-NFR-3 — Resiliency Baseline Compliance, Local Interpretation
- **RESILIENCY-01**: Workload criticality is Low/Personal. Impact of outage: user cannot browse/edit mobile Second Brain until app/link recovers; Mac source remains available.
- **RESILIENCY-02 / 11 / 12 / 13**: Formal DR is N/A per user delegation. Best-effort local recovery is acceptable. Mac Second Brain files are the primary source; Android durable queue/cache protects mobile edits until replay.
- **RESILIENCY-03**: Use existing project change process: GitHub PR/review, CI checks, release artifacts.
- **RESILIENCY-04**: Use existing GitHub Actions and current Mac/APK artifact publishing. Rollback by reinstalling previous artifacts and/or disabling Second Brain sync. Direct install/update is acceptable.
- **RESILIENCY-05 / 06 / 07**: No cloud observability. Local sync state, structured logs, operation results, and reconnect status are required.
- **RESILIENCY-08 / 09**: Regional topology and autoscaling are N/A for local peer-to-peer personal app.
- **RESILIENCY-10**: Mac skill calls and sync operations require explicit timeouts, bounded retries, and graceful offline behavior.
- **RESILIENCY-14**: Validate with automated tests for offline queue, reconnect replay, idempotency, conflict handling, plus manual real-device connectivity test.
- **RESILIENCY-15**: Incidents handled through GitHub issues plus local logs/screenshots.

### MSB-NFR-4 — Performance
- Full sync should avoid unnecessary content transfer by using metadata/version checks or hashes.
- Two-minute background sync must not cause noticeable Android battery drain during idle personal use.
- Local Android search over Markdown cache should return results interactively for a personal Second Brain size.

### MSB-NFR-5 — Reliability
- Pending Android changes must be durable before UI reports them saved.
- Sync replay must be idempotent.
- Partial sync failure must preserve queued changes for retry.
- A failed delete/edit/create operation must not corrupt the local tree cache.

### MSB-NFR-6 — Testability and PBT Compliance
- **PBT-01**: Functional design must identify properties for sync state, queue replay, path normalization, protocol encoding/decoding, and conflict resolution.
- **PBT-02**: Second Brain protocol messages must have encode/decode round-trip PBT in Kotlin and Swift where applicable.
- **PBT-03**: Invariants must be tested: queue order preservation, idempotent replay effects, tree contains unique paths, Markdown-only filters exclude unsupported files.
- **PBT-04**: Sync apply/replay idempotency must have PBT.
- **PBT-05**: Conflict resolution can use a simple reference model as oracle.
- **PBT-06**: Queue and sync state machine require stateful PBT or documented equivalent model tests.
- **PBT-07**: Use domain generators for node paths, Markdown content, operation sequences, timestamps, and sync snapshots.
- **PBT-08**: Seeds and shrinking must remain enabled in CI/local test output.
- **PBT-09**: Use existing Kotest property testing for Kotlin and SwiftCheck for Swift.
- **PBT-10**: Keep example-based tests for concrete create/edit/delete/reconnect/conflict scenarios in addition to PBT.

## Protocol Requirements

- Add protocol messages for:
  - secondBrainTreeRequest / response
  - secondBrainContentRequest / response
  - secondBrainCreate
  - secondBrainUpdate
  - secondBrainDelete
  - secondBrainSyncSnapshot
  - secondBrainPendingChangesPush
  - secondBrainOperationAck / error
- Message schemas must include bounded payload sizes and path validation.
- Operation IDs must support idempotent retry and acknowledgement.
- Content payloads are Markdown text only in this increment.

## Out of Scope

- Non-Markdown attachments or previews.
- Cloud backup, cloud relay, multi-user sync, SaaS sharing.
- Rich Markdown editor beyond basic edit/view unless already trivial in Compose.
- Semantic/LLM Q&A on Android; Android search is local title/content search.
- Multi-device merge beyond one Android device and one Mac unless existing pairing naturally supports it.

## Compliance Summary

### Security
- Applicable rules mapped above. No blocking security findings at requirements stage.

### Resiliency
- Applicable local/personal-use rules mapped above. Cloud-production rules marked N/A with rationale. No blocking resiliency findings at requirements stage.

### PBT
- Full PBT enabled for this increment. Requirements identify PBT surfaces. No blocking PBT findings at requirements stage.
