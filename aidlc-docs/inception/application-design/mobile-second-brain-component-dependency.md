# Mobile Second Brain Component Dependencies

## Dependency Matrix

| Component | Depends On | Used By |
|---|---|---|
| SecondBrainMessageSchema | Existing protocol encoding primitives | Android sync engine, Mac protocol handler, tests |
| SecondBrainProtocolValidator | Message schema | Mac protocol handler, Android inbound response handling |
| MacSecondBrainProtocolHandler | Validator, Mac remote service, secure transport | Existing Mac LinkManager/transport |
| MacSecondBrainRemoteService | Skill gateway, snapshot builder | Mac protocol handler |
| MacSecondBrainSkillGateway | Existing `SecondBrainStore` / skill CLI | Mac remote service |
| MacSecondBrainSyncSnapshotBuilder | Skill gateway | Mac remote service |
| AndroidSecondBrainRepository | Android persistence | UI, sync service, search index |
| AndroidPendingOperationQueue | Android persistence | UI, sync service |
| AndroidSecondBrainSyncEngine | Secure transport, repository, queue, conflict resolver | Android sync service/UI |
| AndroidConflictResolver | Pure model types | Sync engine, PBT |
| AndroidSecondBrainSearchIndex | Repository nodes | UI, repository update hooks |
| AndroidSecondBrainUi | Android service state | User |
| SecondBrainSyncLogger | Platform logging | Mac/Android sync components |
| SecondBrainTestModel | Pure model types | PBT and example tests |

## Communication Pattern

```text
Android UI
  -> AndroidSecondBrainService
  -> Repository + PendingOperationQueue + SearchIndex
  -> AndroidSecondBrainSyncService
  -> Existing secure transport
  -> MacSecondBrainProtocolHandler
  -> MacSecondBrainRemoteService
  -> MacSecondBrainSkillGateway
  -> Existing SecondBrainStore / second-brain skill
```

## Sync Data Flow

```text
Local Android edit
  -> save to Repository
  -> enqueue PendingOperation
  -> display pending count
  -> on secure connection: push operation
  -> Mac validates and applies via skill
  -> Mac returns ack
  -> Android marks acked
  -> Android pulls snapshot/content changes
  -> conflict resolver applies deterministic result
  -> repository/search/UI update
```

## Boundary Rules

- Android never writes Mac filesystem directly.
- Mac filesystem access goes through existing Second Brain skill boundary.
- Protocol layer never accepts unvalidated paths/content.
- UI never talks directly to transport.
- Sync model logic remains pure enough for PBT.

## Coupling Controls

- Protocol schema shared by Kotlin/Swift tests, not ad-hoc string commands.
- Skill CLI details hidden behind `MacSecondBrainSkillGateway`.
- Android persistence hidden behind repository/queue interfaces.
- Conflict resolver isolated from I/O.

## Compliance Summary

### Security
- Validation before dispatch.
- Paired secure channel only.
- No note body logs.

### Resiliency
- Durable Android queue.
- Retry/ack flow.
- Safe partial-failure behavior.

### PBT
- Pure model boundaries identified for properties.
- Protocol and sync state isolated for generated test inputs.
