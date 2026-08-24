package com.androidbridge.core

import com.androidbridge.protocol.ConflictOutcome
import com.androidbridge.protocol.MAX_FRAME_PAYLOAD_BYTES
import com.androidbridge.protocol.SyncOperation
import com.androidbridge.protocol.SyncOperationKind
import com.androidbridge.protocol.SyncModelCodec
import com.androidbridge.protocol.TransferChunk
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import kotlinx.serialization.Serializable

object ContentHash {
    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }
}

enum class SyncJournalError {
    CURSOR_REGRESSION,
    CURSOR_BEYOND_HIGH_WATER,
    STALE_CURSOR,
    SEQUENCE_GAP,
    OPERATION_ID_COLLISION,
    DIGEST_MISMATCH,
    INVALID_CHUNK,
    INCOMPLETE_TRANSFER,
    INVALID_OPERATION,
}

class SyncJournalException(val error: SyncJournalError) : Exception(error.name)

enum class IncomingDisposition { APPLY, DUPLICATE, GAP }

@Serializable
private data class ReceivedOperation(val actorId: String, val sequence: Long)

@Serializable
private data class JournalState(
    val actorId: String,
    val highWater: Long = 0,
    val acknowledgedThrough: Long = 0,
    val operations: List<SyncOperation> = emptyList(),
    val localOperationIds: Set<String> = emptySet(),
    val receivedCursors: Map<String, Long> = emptyMap(),
    val receivedOperations: Map<String, ReceivedOperation> = emptyMap(),
)

class DurableSyncJournal(private val root: File, private val actorId: String) {
    private val stateFile = File(root, "journal.json")
    private val blobDirectory = File(root, "blobs")
    private var state: JournalState

    init {
        require(actorId.isNotEmpty())
        if (!blobDirectory.mkdirs() && !blobDirectory.isDirectory) error("cannot create sync journal")
        state = if (stateFile.exists()) {
            SyncModelCodec.decode(stateFile.readText())
        } else {
            JournalState(actorId)
        }
        require(state.actorId == actorId) { "journal actor mismatch" }
        validateLoadedState()
    }

    val highWater: Long @Synchronized get() = state.highWater
    val acknowledgedThrough: Long @Synchronized get() = state.acknowledgedThrough

    @Synchronized
    fun enqueue(
        operationId: String,
        kind: SyncOperationKind,
        target: String,
        content: ByteArray?,
        baseDigest: String? = null,
        messageType: String? = null,
        mediaType: String? = null,
    ): SyncOperation {
        validateMutation(operationId, kind, target, content, messageType)
        if (operationId in state.localOperationIds) throw SyncJournalException(SyncJournalError.OPERATION_ID_COLLISION)
        val digest = content?.let {
            val hash = ContentHash.sha256(it)
            storeBlob(hash, it)
            hash
        }
        val operation = SyncOperation(
            operationId = operationId,
            actorId = actorId,
            sequence = state.highWater + 1,
            kind = kind,
            target = target,
            messageType = messageType,
            baseDigest = baseDigest,
            resultDigest = digest,
            blobDigest = digest,
            byteCount = content?.size?.toLong() ?: 0,
            mediaType = mediaType,
        )
        commit(state.copy(
            highWater = operation.sequence,
            operations = state.operations + operation,
            localOperationIds = state.localOperationIds + operationId,
        ))
        return operation
    }

    @Synchronized
    fun pending(): List<SyncOperation> = state.operations

    @Synchronized
    fun pending(afterSequence: Long): List<SyncOperation> {
        if (afterSequence < state.acknowledgedThrough) throw SyncJournalException(SyncJournalError.STALE_CURSOR)
        if (afterSequence > state.highWater) throw SyncJournalException(SyncJournalError.CURSOR_BEYOND_HIGH_WATER)
        return state.operations.filter { it.sequence > afterSequence }
    }

    @Synchronized
    fun acknowledge(throughSequence: Long) {
        if (throughSequence < state.acknowledgedThrough) throw SyncJournalException(SyncJournalError.CURSOR_REGRESSION)
        if (throughSequence > state.highWater) throw SyncJournalException(SyncJournalError.CURSOR_BEYOND_HIGH_WATER)
        if (throughSequence == state.acknowledgedThrough) return
        commit(state.copy(
            acknowledgedThrough = throughSequence,
            operations = state.operations.filter { it.sequence > throughSequence },
        ))
        pruneUnreferencedBlobs()
    }

    @Synchronized
    fun incomingDisposition(operation: SyncOperation): IncomingDisposition {
        val seen = state.receivedOperations[operation.operationId]
        if (seen != null) {
            if (seen.actorId != operation.actorId || seen.sequence != operation.sequence) {
                throw SyncJournalException(SyncJournalError.OPERATION_ID_COLLISION)
            }
            return IncomingDisposition.DUPLICATE
        }
        val cursor = state.receivedCursors[operation.actorId] ?: 0
        if (operation.sequence <= cursor) throw SyncJournalException(SyncJournalError.STALE_CURSOR)
        return if (operation.sequence == cursor + 1) IncomingDisposition.APPLY else IncomingDisposition.GAP
    }

    @Synchronized
    fun recordApplied(operation: SyncOperation): Boolean = when (incomingDisposition(operation)) {
        IncomingDisposition.DUPLICATE -> false
        IncomingDisposition.GAP -> throw SyncJournalException(SyncJournalError.SEQUENCE_GAP)
        IncomingDisposition.APPLY -> {
            commit(state.copy(
                receivedCursors = state.receivedCursors + (operation.actorId to operation.sequence),
                receivedOperations = state.receivedOperations +
                    (operation.operationId to ReceivedOperation(operation.actorId, operation.sequence)),
            ))
            true
        }
    }

    @Synchronized
    fun receivedThrough(actorId: String): Long = state.receivedCursors[actorId] ?: 0

    @Synchronized
    fun readBlob(digest: String): ByteArray {
        if (!digest.matches(Regex("[0-9a-f]{64}"))) throw SyncJournalException(SyncJournalError.DIGEST_MISMATCH)
        val bytes = File(blobDirectory, digest).readBytes()
        if (ContentHash.sha256(bytes) != digest) throw SyncJournalException(SyncJournalError.DIGEST_MISMATCH)
        return bytes
    }

    private fun validateMutation(
        operationId: String,
        kind: SyncOperationKind,
        target: String,
        content: ByteArray?,
        messageType: String?,
    ) {
        val invalid = operationId.isEmpty() || target.isEmpty() ||
            (kind == SyncOperationKind.TOMBSTONE && content != null) ||
            (kind != SyncOperationKind.TOMBSTONE && content == null) ||
            (kind == SyncOperationKind.MESSAGE && messageType == null)
        if (invalid) throw SyncJournalException(SyncJournalError.INVALID_OPERATION)
    }

    private fun validateLoadedState() {
        require(state.acknowledgedThrough in 0..state.highWater)
        require(state.operations.zipWithNext().all { (a, b) -> b.sequence == a.sequence + 1 })
        require(state.operations.isEmpty() || state.operations.first().sequence == state.acknowledgedThrough + 1)
        require(state.operations.isEmpty() || state.operations.last().sequence == state.highWater)
        require(state.operations.all { it.actorId == actorId && it.sequence > state.acknowledgedThrough })
        state.operations.mapNotNull { it.blobDigest }.forEach { readBlob(it) }
    }

    private fun storeBlob(digest: String, bytes: ByteArray) {
        val destination = File(blobDirectory, digest)
        if (destination.exists()) {
            if (!destination.readBytes().contentEquals(bytes)) throw SyncJournalException(SyncJournalError.DIGEST_MISMATCH)
            return
        }
        atomicWrite(destination, bytes)
    }

    private fun commit(next: JournalState) {
        atomicWrite(stateFile, SyncModelCodec.encode(next).encodeToByteArray())
        state = next
    }

    private fun pruneUnreferencedBlobs() {
        val retained = state.operations.mapNotNull { it.blobDigest }.toSet()
        blobDirectory.listFiles().orEmpty()
            .filter { it.isFile && it.name !in retained }
            .forEach { if (!it.delete()) error("cannot remove acknowledged sync blob") }
    }

    private fun atomicWrite(destination: File, bytes: ByteArray) {
        val temporary = File(destination.parentFile, ".${destination.name}.${UUID.randomUUID()}.tmp")
        try {
            FileOutputStream(temporary).use { output ->
                output.write(bytes)
                output.fd.sync()
            }
            Files.move(
                temporary.toPath(),
                destination.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } finally {
            temporary.delete()
        }
    }
}

data class NoteConflictResolution(
    val outcome: ConflictOutcome,
    val canonical: ByteArray?,
    val conflict: ByteArray?,
)

object NoteConflictResolver {
    fun resolve(current: ByteArray?, incoming: ByteArray?, baseDigest: String?): NoteConflictResolution {
        val currentDigest = current?.let(ContentHash::sha256)
        val incomingDigest = incoming?.let(ContentHash::sha256)
        if (currentDigest == incomingDigest) {
            return NoteConflictResolution(ConflictOutcome.UNCHANGED, current, null)
        }
        if (currentDigest == baseDigest) {
            val outcome = if (incoming == null) ConflictOutcome.DELETED else ConflictOutcome.APPLIED
            return NoteConflictResolution(outcome, incoming, null)
        }
        return NoteConflictResolution(ConflictOutcome.CONFLICT_PRESERVED, current, incoming)
    }
}

object SyncTransferChunker {
    fun chunk(operationId: String, data: ByteArray, chunkSize: Int): List<TransferChunk> {
        if (chunkSize !in 1..MAX_FRAME_PAYLOAD_BYTES.toInt()) throw SyncJournalException(SyncJournalError.INVALID_CHUNK)
        if (data.isEmpty()) return listOf(makeChunk(operationId, 0, 0, ByteArray(0), true))
        return data.indices.step(chunkSize).mapIndexed { index, offset ->
            val end = minOf(offset + chunkSize, data.size)
            makeChunk(operationId, index, offset.toLong(), data.copyOfRange(offset, end), end == data.size)
        }
    }

    private fun makeChunk(operationId: String, index: Int, offset: Long, bytes: ByteArray, final: Boolean) =
        TransferChunk(
            operationId = operationId,
            index = index,
            offset = offset,
            dataBase64 = Base64.getEncoder().encodeToString(bytes),
            digest = ContentHash.sha256(bytes),
            isFinal = final,
        )
}

class SyncTransferReassembler(
    private val operationId: String,
    private val expectedDigest: String,
) {
    private val output = ByteArrayOutputStream()
    private var nextIndex = 0
    private var complete = false

    fun accept(chunk: TransferChunk) {
        if (complete || chunk.operationId != operationId || chunk.index != nextIndex || chunk.offset != output.size().toLong()) {
            throw SyncJournalException(SyncJournalError.INVALID_CHUNK)
        }
        val bytes = try {
            chunk.decodedData()
        } catch (_: IllegalArgumentException) {
            throw SyncJournalException(SyncJournalError.INVALID_CHUNK)
        }
        if (bytes.size > MAX_FRAME_PAYLOAD_BYTES || ContentHash.sha256(bytes) != chunk.digest) {
            throw SyncJournalException(SyncJournalError.DIGEST_MISMATCH)
        }
        output.write(bytes)
        nextIndex++
        complete = chunk.isFinal
    }

    fun result(): ByteArray {
        if (!complete) throw SyncJournalException(SyncJournalError.INCOMPLETE_TRANSFER)
        val result = output.toByteArray()
        if (ContentHash.sha256(result) != expectedDigest) throw SyncJournalException(SyncJournalError.DIGEST_MISMATCH)
        return result
    }
}
