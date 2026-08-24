package com.androidbridge.core

import com.androidbridge.protocol.ConflictOutcome
import com.androidbridge.protocol.SyncModelCodec
import com.androidbridge.protocol.SyncOperation
import com.androidbridge.protocol.SyncOperationKind
import java.io.File
import java.io.FileOutputStream
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import kotlinx.serialization.Serializable

data class BrainSyncFile(val path: String, val bytes: ByteArray)

interface BrainSyncStorage {
    fun files(): List<BrainSyncFile>
    fun read(path: String): ByteArray?
    fun write(path: String, bytes: ByteArray)
    fun delete(path: String)
}

object BrainSyncPolicy {
    private const val MEETING_PROJECTION = "meetings/android-bridge/"
    private val pngSignature = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)

    fun mediaType(path: String, bytes: ByteArray): String? {
        if (isSyncConflictPath(path)) return null
        return writableMediaType(path, bytes)
    }

    fun writableMediaType(path: String, bytes: ByteArray): String? {
        if (!safeRelativePath(path)) return null
        return when {
            path.endsWith(".md") -> "text/markdown"
            path.startsWith(MEETING_PROJECTION) && (path.endsWith(".jpg") || path.endsWith(".jpeg")) && isJpeg(bytes) -> "image/jpeg"
            path.startsWith(MEETING_PROJECTION) && path.endsWith(".png") && bytes.startsWith(pngSignature) -> "image/png"
            else -> null
        }
    }

    fun allowsTombstone(path: String): Boolean {
        if (!safeRelativePath(path) || isSyncConflictPath(path)) return false
        return path.endsWith(".md") || path.startsWith(MEETING_PROJECTION) &&
            (path.endsWith(".jpg") || path.endsWith(".jpeg") || path.endsWith(".png"))
    }

    private fun safeRelativePath(path: String): Boolean {
        if (path.isEmpty() || path.length > 1024 || path.startsWith('/') || '\\' in path || ':' in path) return false
        if (path.any(Char::isISOControl)) return false
        return path.split('/').all { it.isNotEmpty() && it != "." && it != ".." }
    }

    private fun isJpeg(bytes: ByteArray): Boolean = bytes.size >= 5 &&
        bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() && bytes[2] == 0xff.toByte() &&
        bytes[bytes.lastIndex - 1] == 0xff.toByte() && bytes.last() == 0xd9.toByte()

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }
}

@Serializable
private data class BrainSyncManifestState(val paths: Map<String, String> = emptyMap())

class BrainSyncManifest(private val file: File) {
    private var state = if (file.exists()) {
        SyncModelCodec.decode<BrainSyncManifestState>(file.readText())
    } else {
        BrainSyncManifestState()
    }

    init {
        require(state.paths.all { (path, digest) -> BrainSyncPolicy.allowsTombstone(path) && digest.isDigest() })
    }

    @Synchronized
    fun hashes(): Map<String, String> = state.paths.toMap()

    @Synchronized
    fun update(path: String, digest: String?) {
        require(BrainSyncPolicy.allowsTombstone(path))
        require(digest == null || digest.isDigest())
        val paths = if (digest == null) state.paths - path else state.paths + (path to digest)
        persist(BrainSyncManifestState(paths))
    }

    private fun persist(next: BrainSyncManifestState) {
        file.parentFile?.let { if (!it.mkdirs() && !it.isDirectory) error("cannot create brain sync manifest directory") }
        val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}.tmp")
        try {
            FileOutputStream(temporary).use { output ->
                output.write(SyncModelCodec.encode(next).encodeToByteArray())
                output.fd.sync()
            }
            try {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
            state = next
        } finally {
            temporary.delete()
        }
    }
}

class BrainSyncCoordinator(
    private val journal: DurableSyncJournal,
    private val manifest: BrainSyncManifest,
    private val storage: BrainSyncStorage,
) {
    @Synchronized
    fun captureChanges(): List<SyncOperation> {
        val previous = manifest.hashes()
        val current = storage.files().mapNotNull { file ->
            BrainSyncPolicy.mediaType(file.path, file.bytes)?.let { mediaType ->
                Triple(file, mediaType, ContentHash.sha256(file.bytes))
            }
        }.associateBy { it.first.path }
        val snapshots = current.values.sortedBy { it.first.path }.mapNotNull { (file, mediaType, digest) ->
            if (previous[file.path] == digest) return@mapNotNull null
            journal.enqueue(
                operationId = UUID.randomUUID().toString(),
                kind = SyncOperationKind.SNAPSHOT,
                target = file.path,
                content = file.bytes,
                baseDigest = previous[file.path],
                mediaType = mediaType,
            ).also { manifest.update(file.path, digest) }
        }
        val tombstones = (previous.keys - current.keys).sorted().map { path ->
            journal.enqueue(
                operationId = UUID.randomUUID().toString(),
                kind = SyncOperationKind.TOMBSTONE,
                target = path,
                content = null,
                baseDigest = previous.getValue(path),
            ).also { manifest.update(path, null) }
        }
        return snapshots + tombstones
    }

    @Synchronized
    fun applyIncoming(operation: SyncOperation, bytes: ByteArray?): ConflictOutcome {
        validateIncoming(operation, bytes)
        val current = storage.read(operation.target)
        val resolution = NoteConflictResolver.resolve(current, bytes, operation.baseDigest)
        when (resolution.outcome) {
            ConflictOutcome.UNCHANGED -> manifest.update(operation.target, bytes?.let(ContentHash::sha256))
            ConflictOutcome.APPLIED -> {
                storage.write(operation.target, requireNotNull(bytes))
                manifest.update(operation.target, operation.resultDigest)
            }
            ConflictOutcome.DELETED -> {
                storage.delete(operation.target)
                manifest.update(operation.target, null)
            }
            ConflictOutcome.CONFLICT_PRESERVED -> (resolution.conflict ?: resolution.canonical)?.let {
                storage.write(conflictPath(operation), it)
            }
        }
        return resolution.outcome
    }

    private fun validateIncoming(operation: SyncOperation, bytes: ByteArray?) {
        operation.baseDigest?.let { require(it.isDigest()) }
        when (operation.kind) {
            SyncOperationKind.SNAPSHOT -> {
                val content = requireNotNull(bytes)
                val digest = ContentHash.sha256(content)
                require(operation.resultDigest == digest && operation.blobDigest == digest)
                require(operation.byteCount == content.size.toLong())
                require(operation.mediaType == BrainSyncPolicy.mediaType(operation.target, content))
                require(operation.messageType == null)
            }
            SyncOperationKind.TOMBSTONE -> {
                require(bytes == null && BrainSyncPolicy.allowsTombstone(operation.target))
                require(operation.resultDigest == null && operation.blobDigest == null && operation.mediaType == null)
                require(operation.byteCount == 0L && operation.messageType == null)
            }
            else -> error("Unsupported brain sync operation")
        }
    }

    private fun conflictPath(operation: SyncOperation): String {
        val hash = ContentHash.sha256(operation.operationId.encodeToByteArray())
        val digits = hash.take(14).map { Character.digit(it, 16) % 10 }.joinToString("")
        val marker = ".sync-conflict-${digits.take(8)}-${digits.drop(8)}-${hash.take(7).uppercase()}"
        val extensionIndex = operation.target.lastIndexOf('.')
        return operation.target.substring(0, extensionIndex) + marker + operation.target.substring(extensionIndex)
    }
}

private fun String.isDigest(): Boolean = matches(Regex("[0-9a-f]{64}"))
