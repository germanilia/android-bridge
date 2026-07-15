# Mobile Second Brain Services

## AndroidSecondBrainService

Primary Android orchestration service for UI, repository, queue, search, and sync engine.

**Responsibilities**
- Load UI state from repository and queue.
- Accept create/edit/delete commands from UI.
- Persist local changes and enqueue operations.
- Trigger search index updates.
- Start Sync Now.

**Interactions**
- Depends on `AndroidSecondBrainRepository`, `AndroidPendingOperationQueue`, `AndroidSecondBrainSearchIndex`, and `AndroidSecondBrainSyncEngine`.

## AndroidSecondBrainSyncService

Background sync orchestration around connection state.

**Responsibilities**
- Observe paired-device connection state.
- Start two-minute periodic sync while connected.
- Trigger immediate pending replay on reconnect.
- Coordinate push-then-pull sync flow.
- Surface sync state to UI.

**Interactions**
- Uses existing secure transport.
- Sends protocol messages to Mac handler.
- Updates repository and queue from acknowledgements/responses.

## MacSecondBrainRemoteService

Mac-side service exposed to paired Android device.

**Responsibilities**
- Receive validated requests from protocol handler.
- Call skill gateway for filesystem operations.
- Build sync snapshots and operation acknowledgements.
- Enforce timeouts and safe errors.

**Interactions**
- Depends on `MacSecondBrainSkillGateway` and `MacSecondBrainSyncSnapshotBuilder`.

## Sync Orchestration Pattern

1. Android detects secure connection or two-minute timer/Sync Now fires.
2. Android validates feature enabled and pushes pending operations with operation IDs.
3. Mac validates each operation and applies via Second Brain skill gateway.
4. Mac returns ack/failure per operation.
5. Android marks acked operations and leaves failed operations queued where retryable.
6. Android requests Mac snapshot.
7. Android compares snapshot to local metadata.
8. Android pulls changed Markdown content and applies conflict resolution where needed.
9. Android rebuilds/updates local search index.
10. UI displays last success/failure and pending count.

## Error Handling Pattern

- Validation/auth errors fail closed and do not mutate local data.
- Skill failures become safe protocol errors.
- Retryable sync failures keep operations queued.
- Non-retryable invalid operations are marked failed with safe reason.
- Logs omit note bodies.

## Security Pattern

- Only existing paired mTLS channel carries messages.
- Feature-level toggle/permission gates Mac request dispatch.
- Message validation happens before handler dispatch.
- Android cache and queue use protected local storage.

## Resiliency Pattern

- Best-effort personal local recovery.
- Android queue is durable.
- Operation IDs make retries idempotent.
- Mac source remains authoritative for filesystem state.
- Rollback is previous artifact reinstall or feature disable.

## PBT Pattern

- Protocol encode/decode round trip.
- Queue replay idempotency.
- Conflict resolver oracle/model.
- Tree uniqueness and Markdown-only invariants.
- Stateful sync model command sequences.
