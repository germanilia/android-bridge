# Mobile Second Brain Application Design

## Scope

Application design for Increment 8: Android Mobile Second Brain sync/view/edit backed by the Mac Second Brain skill.

## Design Summary

The design introduces a local-first Android Second Brain feature with a Mac skill-backed remote service. Android owns offline UX, local cache, pending operation queue, local search, and sync state. Mac owns real filesystem access through the existing Second Brain skill/`SecondBrainStore` boundary. Shared protocol messages carry validated Markdown-only operations over the existing paired mTLS transport.

## Components

See `mobile-second-brain-components.md`.

Key components:
- `SecondBrainMessageSchema`
- `SecondBrainProtocolValidator`
- `MacSecondBrainProtocolHandler`
- `MacSecondBrainSkillGateway`
- `MacSecondBrainSyncSnapshotBuilder`
- `AndroidSecondBrainRepository`
- `AndroidPendingOperationQueue`
- `AndroidSecondBrainSyncEngine`
- `AndroidConflictResolver`
- `AndroidSecondBrainSearchIndex`
- `AndroidSecondBrainUi`
- `SecondBrainSyncLogger`
- `SecondBrainTestModel`

## Methods

See `mobile-second-brain-component-methods.md`.

High-level interfaces cover:
- Protocol encode/decode/validation.
- Mac tree/content/CRUD/sync handlers.
- Mac skill gateway operations.
- Android repository/cache operations.
- Android pending queue operations.
- Sync engine periodic/manual/reconnect flows.
- Search and UI actions.

## Services

See `mobile-second-brain-services.md`.

Service layer:
- `AndroidSecondBrainService`: UI-facing orchestration.
- `AndroidSecondBrainSyncService`: connection-aware periodic/reconnect sync.
- `MacSecondBrainRemoteService`: Mac-side skill-backed operation service.

## Dependencies

See `mobile-second-brain-component-dependency.md`.

Main flow:

```text
Android UI -> Android service -> repository/queue/search -> sync engine -> secure transport -> Mac handler -> Mac remote service -> skill gateway -> SecondBrainStore/skill
```

## Key Design Decisions

1. **Mac skill boundary remains authoritative**
   - Android never writes the Mac filesystem directly.
   - Mac applies changes through existing skill/CLI wrapper.

2. **Android is offline-first**
   - Full Markdown tree/content cached locally.
   - CRUD works offline by writing cache and queue.
   - Queue survives restart.

3. **Sync is operation-ID based**
   - Each local change receives an operation ID.
   - Retry is idempotent.
   - Acknowledgements remove successful operations from queue.

4. **Conflict logic is pure**
   - Last-write-wins by timestamp.
   - Deterministic tie-breaker must be defined in Functional Design.
   - No note body content in conflict logs.

5. **Search is local on Android**
   - Title/path/content index over cached Markdown.
   - Works offline.

## Security Compliance

- SECURITY-01: Existing mTLS channel; protected Android cache/queue.
- SECURITY-03: Structured logs; no note bodies/secrets.
- SECURITY-05: Protocol validator before dispatch.
- SECURITY-08: Paired authenticated device only; feature-level gate.
- SECURITY-09: Safe user-facing errors.
- SECURITY-10: Existing pinned dependencies and CI conventions.
- SECURITY-12: No hardcoded secrets.
- SECURITY-13: Safe schema decoding.
- SECURITY-14: Local failed auth/validation/sync logs without content.
- SECURITY-15: Fail closed on invalid/auth errors.
- N/A: Cloud/web-specific rules.

No blocking security findings.

## Resiliency Compliance

- Local/personal workload, low criticality.
- No formal cloud DR; best-effort recovery through Mac source and Android durable queue/cache.
- Existing GitHub/CI/artifact process.
- Rollback by previous artifacts and/or feature disable.
- No cloud region/autoscaling topology.
- Explicit timeouts and bounded retry required in Functional/NFR Design.

No blocking resiliency findings.

## PBT Compliance

Design creates PBT-friendly pure boundaries:
- Protocol round trip.
- Queue replay and idempotency.
- Conflict resolver oracle/model.
- Tree/path/Markdown-only invariants.
- Stateful sync model command sequences.

No blocking PBT findings.

## Open Items for Functional Design

- Exact Android persistence technology already present vs new store.
- Timestamp source and deterministic tie-breaker for equal timestamps/clock skew.
- Hash/version algorithm for efficient sync.
- Retry classification: retryable vs permanent failures.
- Maximum Markdown file size and sync batch size.
