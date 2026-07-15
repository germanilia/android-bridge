# Mobile Second Brain Components

## Protocol Components

### SecondBrainMessageSchema
Defines wire messages for tree, content, CRUD, sync snapshots, pending operation push, acknowledgements, and errors.

**Responsibilities**
- Represent Markdown-only Second Brain operations.
- Include operation IDs for idempotent retry.
- Include bounded content payloads, timestamps, paths, and source metadata.
- Support Kotlin and Swift encode/decode round-trip PBT.

### SecondBrainProtocolValidator
Validates all inbound Second Brain messages before dispatch.

**Responsibilities**
- Validate message type, path format, `.md` extension, payload size, timestamp, and operation ID.
- Reject unsupported file types and malformed operations.
- Fail closed on validation errors.

## Mac Components

### MacSecondBrainProtocolHandler
Receives authenticated Second Brain protocol requests from Android and maps them to Mac services.

**Responsibilities**
- Authorize requests from paired device only.
- Dispatch tree/content/create/update/delete/sync requests.
- Return acknowledgements and safe errors.
- Avoid logging note bodies.

### MacSecondBrainSkillGateway
Wraps existing `SecondBrainStore` / second-brain skill operations behind a sync-safe API.

**Responsibilities**
- Read full tree and Markdown content from the Mac Second Brain.
- Apply create/update/delete operations through the skill boundary.
- Enforce operation timeouts.
- Normalize skill errors to safe protocol errors.

### MacSecondBrainSyncSnapshotBuilder
Builds Mac-side snapshots for Android sync.

**Responsibilities**
- Produce node metadata: path, modified timestamp, hash/version, deleted flag where relevant.
- Load content only when needed by sync.
- Keep snapshot generation bounded for personal-use scale.

## Android Components

### AndroidSecondBrainRepository
Owns Android local Second Brain data state.

**Responsibilities**
- Persist full Markdown tree and content cache.
- Expose read/write APIs to UI and sync engine.
- Store node metadata, content, last modified, source, and sync state.

### AndroidPendingOperationQueue
Durable queue for offline create/update/delete operations.

**Responsibilities**
- Persist operations before UI reports saved.
- Preserve operation order.
- Mark operations acknowledged or failed.
- Survive app/process/device restart.

### AndroidSecondBrainSyncEngine
Coordinates bidirectional sync with Mac.

**Responsibilities**
- Run periodic two-minute sync while connected.
- Run Sync Now on demand.
- Push pending operations on reconnect.
- Pull Mac changes into local cache.
- Use idempotent operation IDs and acknowledgements.

### AndroidConflictResolver
Pure conflict resolution component.

**Responsibilities**
- Apply last-write-wins by timestamp.
- Provide deterministic tie-breaker for equal timestamps or clock skew cases.
- Return conflict log metadata without content.

### AndroidSecondBrainSearchIndex
Searches locally cached Markdown nodes.

**Responsibilities**
- Index title/path and content.
- Return path/title/snippet results offline.
- Update index after sync and local edits.

### AndroidSecondBrainUi
Jetpack Compose screen/tab for Second Brain.

**Responsibilities**
- Browse tree, read content, edit/create/delete Markdown nodes.
- Show sync state, pending count, last sync, and errors.
- Trigger Sync Now.

## Cross-Cutting Components

### SecondBrainSyncLogger
Structured local logging for sync events.

**Responsibilities**
- Log operation IDs, paths when needed, timestamps, result status.
- Never log note bodies, secrets, or credentials.

### SecondBrainTestModel
Pure reference/model layer used for PBT and example tests.

**Responsibilities**
- Model operation replay, idempotency, tree uniqueness, conflict resolution, and protocol round trips.
