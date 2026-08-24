package com.androidbridge.relay

import com.androidbridge.core.DurableSyncJournal
import com.androidbridge.core.IncomingDisposition
import com.androidbridge.core.SyncTransferChunker
import com.androidbridge.core.SyncTransferReassembler
import com.androidbridge.protocol.CapabilityAnnouncement
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import com.androidbridge.protocol.MessageTypes
import com.androidbridge.protocol.ReplayClassification
import com.androidbridge.protocol.ReplayClassifier
import com.androidbridge.protocol.ResumeRequest
import com.androidbridge.protocol.SyncAcknowledgement
import com.androidbridge.protocol.SyncCapability
import com.androidbridge.protocol.SyncCursor
import com.androidbridge.protocol.SyncModelCodec
import com.androidbridge.protocol.SyncOperation
import com.androidbridge.protocol.SyncOperationKind
import com.androidbridge.protocol.TransferChunk
import com.androidbridge.protocol.validate
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import java.util.UUID

internal data class RelayReplayResult(
    val messages: List<Message> = emptyList(),
    val outboundFrames: List<ByteArray> = emptyList(),
)

internal class AndroidRelayReplaySession(
    private val journal: DurableSyncJournal,
    private val actorId: String,
    private val peerActorId: String,
    private val messageApplier: (Message) -> Unit = { error("No relay message applier configured") },
    private val syncOperationApplier: (SyncOperation, ByteArray?) -> Unit = { _, _ ->
        error("No sync operation applier configured")
    },
) {
    private val incoming = mutableMapOf<String, SyncOperation>()
    private val reassemblers = mutableMapOf<String, SyncTransferReassembler>()
    private val ignored = mutableSetOf<String>()

    fun enqueue(message: Message): List<ByteArray> {
        if (ReplayClassifier.classify(message.type) == ReplayClassification.LIVE_ONLY) {
            return listOf(MessageCodec.encode(message))
        }
        val bytes = encodeDurableMessage(message)
        val operation = journal.enqueue(
            operationId = message.id,
            kind = SyncOperationKind.MESSAGE,
            target = message.id,
            content = bytes,
            messageType = message.type,
            mediaType = "application/vnd.androidbridge.message",
        )
        return operationFrames(operation)
    }

    fun sessionFrames(): List<ByteArray> {
        val capability = CapabilityAnnouncement(
            actorId,
            listOf(SyncCapability.DURABLE_SYNC, SyncCapability.RESUMABLE_TRANSFER, SyncCapability.NOTE_CONFLICTS),
        )
        val resume = ResumeRequest(SyncCursor(peerActorId, journal.receivedThrough(peerActorId)))
        return buildList {
            add(frame(MessageTypes.SYNC_CAPABILITIES, capability))
            add(frame(MessageTypes.SYNC_RESUME, resume))
            journal.pending().forEach { addAll(operationFrames(it)) }
        }
    }

    fun handle(message: Message): RelayReplayResult = when (message.type) {
        MessageTypes.SYNC_ACK -> {
            apply(model<SyncAcknowledgement>(message))
            RelayReplayResult()
        }
        MessageTypes.SYNC_RESUME -> resume(model(message))
        MessageTypes.SYNC_OPERATION -> accept(model<SyncOperation>(message))
        MessageTypes.SYNC_TRANSFER_CHUNK -> accept(model<TransferChunk>(message))
        MessageTypes.SYNC_CAPABILITIES -> {
            model<CapabilityAnnouncement>(message)
            RelayReplayResult()
        }
        else -> RelayReplayResult(messages = listOf(message))
    }

    private fun resume(request: ResumeRequest): RelayReplayResult {
        require(request.cursor.actorId == actorId) { "Unexpected relay actor" }
        return RelayReplayResult(outboundFrames = journal.pending(request.cursor.throughSequence).flatMap(::operationFrames))
    }

    private fun apply(ack: SyncAcknowledgement) {
        require(ack.cursor.actorId == actorId) { "Unexpected relay actor" }
        if (ack.cursor.throughSequence <= journal.acknowledgedThrough) return
        val operation = journal.pending().firstOrNull { it.sequence == ack.cursor.throughSequence }
        require(operation?.operationId == ack.operationId) { "Unexpected relay acknowledgement" }
        journal.acknowledge(ack.cursor.throughSequence)
    }

    private fun accept(operation: SyncOperation): RelayReplayResult {
        require(operation.actorId == peerActorId) { "Unexpected relay actor" }
        validateIncoming(operation)
        return when (journal.incomingDisposition(operation)) {
            IncomingDisposition.DUPLICATE -> {
                if (operation.blobDigest != null) ignored += operation.operationId
                RelayReplayResult(outboundFrames = listOf(acknowledgementFrame(operation)))
            }
            IncomingDisposition.GAP -> {
                if (operation.blobDigest != null) ignored += operation.operationId
                val cursor = SyncCursor(operation.actorId, journal.receivedThrough(operation.actorId))
                RelayReplayResult(outboundFrames = listOf(frame(MessageTypes.SYNC_RESUME, ResumeRequest(cursor))))
            }
            IncomingDisposition.APPLY -> acceptNew(operation)
        }
    }

    private fun acceptNew(operation: SyncOperation): RelayReplayResult {
        if (operation.kind == SyncOperationKind.TOMBSTONE) {
            syncOperationApplier(operation, null)
            journal.recordApplied(operation)
            return RelayReplayResult(outboundFrames = listOf(acknowledgementFrame(operation)))
        }
        val digest = requireNotNull(operation.resultDigest)
        incoming[operation.operationId] = operation
        reassemblers[operation.operationId] = SyncTransferReassembler(operation.operationId, digest)
        return RelayReplayResult()
    }

    private fun accept(chunk: TransferChunk): RelayReplayResult {
        if (chunk.operationId in ignored) {
            if (chunk.isFinal) ignored -= chunk.operationId
            return RelayReplayResult()
        }
        val operation = requireNotNull(incoming[chunk.operationId]) { "Unknown relay operation" }
        val reassembler = requireNotNull(reassemblers[chunk.operationId]) { "Unknown relay transfer" }
        val chunkSize = chunk.decodedData().size.toLong()
        require(chunk.offset in 0..operation.byteCount && chunkSize <= operation.byteCount - chunk.offset) {
            "Relay chunk exceeds declared size"
        }
        reassembler.accept(chunk)
        if (!chunk.isFinal) return RelayReplayResult()
        val bytes = reassembler.result()
        val original = if (operation.kind == SyncOperationKind.MESSAGE) {
            decodeDurableMessage(bytes).also { require(it.type == operation.messageType) { "Relay message type mismatch" } }
        } else null
        journal.recordApplied(operation) {
            if (original != null) messageApplier(original) else syncOperationApplier(operation, bytes)
        }
        incoming -= chunk.operationId
        reassemblers -= chunk.operationId
        return RelayReplayResult(
            messages = emptyList(),
            outboundFrames = listOf(acknowledgementFrame(operation)),
        )
    }

    fun framesFor(operations: List<SyncOperation>): List<ByteArray> = operations.flatMap(::operationFrames)

    private fun validateIncoming(operation: SyncOperation) {
        when (operation.kind) {
            SyncOperationKind.MESSAGE -> require(
                operation.messageType != null && operation.resultDigest != null &&
                    operation.blobDigest == operation.resultDigest && operation.byteCount in 0..MAX_SYNC_FILE_BYTES,
            )
            SyncOperationKind.SNAPSHOT -> require(
                operation.messageType == null && operation.resultDigest != null &&
                    operation.blobDigest == operation.resultDigest && operation.byteCount in 0..MAX_SYNC_FILE_BYTES,
            )
            SyncOperationKind.TOMBSTONE -> require(
                operation.messageType == null && operation.resultDigest == null && operation.blobDigest == null &&
                    operation.byteCount == 0L && operation.mediaType == null,
            )
            SyncOperationKind.TRANSFER -> error("Unsupported relay sync operation")
        }
    }

    private fun operationFrames(operation: SyncOperation): List<ByteArray> = buildList {
        add(frame(MessageTypes.SYNC_OPERATION, operation))
        operation.blobDigest?.let { digest ->
            val bytes = journal.readBlob(digest)
            SyncTransferChunker.chunk(operation.operationId, bytes, 32_768)
                .forEach { add(frame(MessageTypes.SYNC_TRANSFER_CHUNK, it)) }
        }
    }

    private fun encodeDurableMessage(message: Message): ByteArray =
        SyncModelCodec.json.encodeToString(Message.serializer(), message).encodeToByteArray().also {
            require(it.size <= MAX_SYNC_FILE_BYTES) { "Relay message is too large" }
        }

    private fun decodeDurableMessage(bytes: ByteArray): Message {
        require(bytes.size <= MAX_SYNC_FILE_BYTES) { "Relay message is too large" }
        val message = SyncModelCodec.json.decodeFromString(Message.serializer(), bytes.decodeToString())
        require(validate(message).valid) { "Invalid relay message" }
        return message
    }

    private fun acknowledgementFrame(operation: SyncOperation): ByteArray = frame(
        MessageTypes.SYNC_ACK,
        SyncAcknowledgement(SyncCursor(operation.actorId, operation.sequence), operation.operationId),
    )

    private inline fun <reified T> frame(type: String, model: T): ByteArray {
        val payload = SyncModelCodec.json.encodeToJsonElement(model) as JsonObject
        return MessageCodec.encode(Message(UUID.randomUUID().toString(), type, payload = payload))
    }

    private inline fun <reified T> model(message: Message): T =
        SyncModelCodec.json.decodeFromJsonElement(message.payload)

    private companion object {
        const val MAX_SYNC_FILE_BYTES = 25L * 1024 * 1024
    }
}
