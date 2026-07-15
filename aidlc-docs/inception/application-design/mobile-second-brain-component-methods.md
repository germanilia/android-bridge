# Mobile Second Brain Component Methods

## Protocol

### SecondBrainMessageSchema
```text
encode(message: SecondBrainMessage) -> ByteArray/Data
decode(bytes: ByteArray/Data) -> SecondBrainMessage
```

### SecondBrainProtocolValidator
```text
validate(message: SecondBrainMessage) -> ValidationResult
validatePath(path: String) -> ValidationResult
validatePayloadSize(message: SecondBrainMessage) -> ValidationResult
```

## Mac

### MacSecondBrainProtocolHandler
```text
handleTreeRequest(request, peer) -> TreeResponse
handleContentRequest(request, peer) -> ContentResponse
handleCreate(request, peer) -> OperationAck
handleUpdate(request, peer) -> OperationAck
handleDelete(request, peer) -> OperationAck
handleSyncSnapshot(request, peer) -> SyncSnapshotResponse
handlePendingChangesPush(request, peer) -> PendingChangesAck
```

### MacSecondBrainSkillGateway
```text
loadTree() -> [SecondBrainNodeMetadata]
loadContent(path: String) -> MarkdownContent
createNode(path: String, content: String, modifiedAt: Instant) -> SkillOperationResult
updateNode(path: String, content: String, modifiedAt: Instant) -> SkillOperationResult
deleteNode(path: String, modifiedAt: Instant) -> SkillOperationResult
```

### MacSecondBrainSyncSnapshotBuilder
```text
buildSnapshot() -> SecondBrainSyncSnapshot
metadataFor(path: String) -> SecondBrainNodeMetadata
contentForChangedNode(path: String) -> MarkdownContent
```

## Android

### AndroidSecondBrainRepository
```text
loadTree() -> SecondBrainTree
loadNode(path: String) -> SecondBrainNode
saveLocalNode(path: String, content: String, modifiedAt: Instant) -> SecondBrainNode
deleteLocalNode(path: String, modifiedAt: Instant) -> Unit
applyRemoteSnapshot(snapshot: SecondBrainSyncSnapshot) -> SyncApplyResult
applyRemoteContent(path: String, content: String, metadata: NodeMetadata) -> Unit
```

### AndroidPendingOperationQueue
```text
enqueue(operation: PendingSecondBrainOperation) -> OperationId
pendingOperations() -> [PendingSecondBrainOperation]
markAcknowledged(operationId: OperationId) -> Unit
markFailed(operationId: OperationId, safeReason: String) -> Unit
pendingCount() -> Int
```

### AndroidSecondBrainSyncEngine
```text
startPeriodicSync(interval: Duration = 2 minutes) -> Unit
stopPeriodicSync() -> Unit
syncNow(trigger: SyncTrigger) -> SyncResult
onConnectionRestored() -> Unit
pushPendingOperations() -> PendingPushResult
pullRemoteChanges() -> PullResult
```

### AndroidConflictResolver
```text
resolve(local: NodeVersion, remote: NodeVersion) -> ConflictResolution
compareVersions(local: NodeVersion, remote: NodeVersion) -> VersionWinner
```

### AndroidSecondBrainSearchIndex
```text
rebuild(nodes: [SecondBrainNode]) -> Unit
update(node: SecondBrainNode) -> Unit
remove(path: String) -> Unit
search(query: String) -> [SecondBrainSearchResult]
```

### AndroidSecondBrainUi
```text
renderSecondBrainScreen(state: SecondBrainUiState)
onNodeSelected(path: String)
onCreateNode(path: String, content: String)
onSaveNode(path: String, content: String)
onDeleteNode(path: String)
onSyncNow()
onSearch(query: String)
```

## Cross-Cutting

### SecondBrainSyncLogger
```text
logSyncStarted(trigger: SyncTrigger)
logOperationResult(operationId: OperationId, path: String, status: OperationStatus)
logConflict(path: String, localTimestamp: Instant, remoteTimestamp: Instant, winner: Source)
logValidationFailure(reason: String)
```

### SecondBrainTestModel
```text
apply(model: SyncModel, operation: PendingSecondBrainOperation) -> SyncModel
resolveConflict(local: NodeVersion, remote: NodeVersion) -> NodeVersion
assertInvariants(model: SyncModel) -> Bool
```
