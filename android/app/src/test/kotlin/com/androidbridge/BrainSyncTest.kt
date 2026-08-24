package com.androidbridge

import com.androidbridge.core.BrainSyncCoordinator
import com.androidbridge.core.BrainSyncFile
import com.androidbridge.core.BrainSyncManifest
import com.androidbridge.core.BrainSyncStorage
import com.androidbridge.core.ContentHash
import com.androidbridge.core.DurableSyncJournal
import com.androidbridge.protocol.ConflictOutcome
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import com.androidbridge.protocol.MessageTypes
import com.androidbridge.protocol.SyncAcknowledgement
import com.androidbridge.protocol.SyncModelCodec
import com.androidbridge.protocol.SyncOperation
import com.androidbridge.protocol.SyncOperationKind
import com.androidbridge.protocol.TransferChunk
import com.androidbridge.relay.AndroidRelayReplaySession
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import java.nio.file.Files
import java.util.Base64

class BrainSyncTest : StringSpec({
    "scan emits only relative Markdown and validated meeting images, then becomes a no-op" {
        withBrainSync { coordinator, storage, journal ->
            storage.files["notes/a.md"] = "hello".encodeToByteArray()
            storage.files["meetings/android-bridge/photo.jpg"] = jpeg()
            storage.files["meetings/android-bridge/image.png"] = png()
            storage.files["meetings/android-bridge/audio.m4a"] = byteArrayOf(1, 2)
            storage.files["photos/outside.jpg"] = jpeg()
            storage.files["/absolute.md"] = "no".encodeToByteArray()
            storage.files["meetings/android-bridge/fake.jpg"] = png()

            coordinator.captureChanges().map { it.target }.toSet() shouldBe setOf(
                "notes/a.md",
                "meetings/android-bridge/photo.jpg",
                "meetings/android-bridge/image.png",
            )
            coordinator.captureChanges() shouldBe emptyList()
            journal.pending() shouldHaveSize 3
        }
    }

    "scan records hash bases and turns a removal into an immutable tombstone" {
        withBrainSync { coordinator, storage, _ ->
            storage.files["notes/a.md"] = "one".encodeToByteArray()
            val first = coordinator.captureChanges().single()
            first.baseDigest shouldBe null

            storage.files["notes/a.md"] = "two".encodeToByteArray()
            val second = coordinator.captureChanges().single()
            second.baseDigest shouldBe ContentHash.sha256("one".encodeToByteArray())

            storage.files.remove("notes/a.md")
            val tombstone = coordinator.captureChanges().single()
            tombstone.kind shouldBe SyncOperationKind.TOMBSTONE
            tombstone.baseDigest shouldBe ContentHash.sha256("two".encodeToByteArray())
        }
    }

    "incoming compare-and-set applies without echo and preserves a stable visible conflict sibling" {
        withBrainSync { coordinator, storage, _ ->
            storage.files["notes/a.md"] = "base".encodeToByteArray()
            coordinator.captureChanges()

            val incoming = snapshot(1, "notes/a.md", "remote", ContentHash.sha256("base".encodeToByteArray()))
            coordinator.applyIncoming(incoming, "remote".encodeToByteArray()) shouldBe ConflictOutcome.APPLIED
            storage.files["notes/a.md"]!!.decodeToString() shouldBe "remote"
            coordinator.captureChanges() shouldBe emptyList()

            storage.files["notes/a.md"] = "local".encodeToByteArray()
            val conflict = snapshot(2, "notes/a.md", "other", ContentHash.sha256("base".encodeToByteArray()))
            coordinator.applyIncoming(conflict, "other".encodeToByteArray()) shouldBe ConflictOutcome.CONFLICT_PRESERVED
            storage.files["notes/a.md"]!!.decodeToString() shouldBe "local"
            val sibling = storage.files.keys.single { it.contains(".sync-conflict-") }
            storage.files[sibling]!!.decodeToString() shouldBe "other"
            coordinator.applyIncoming(conflict, "other".encodeToByteArray()) shouldBe ConflictOutcome.CONFLICT_PRESERVED
            storage.files.keys.count { it.contains(".sync-conflict-") } shouldBe 1
            coordinator.captureChanges().single().target shouldBe "notes/a.md"
        }
    }

    "tombstone CAS conflict keeps canonical content and one stable non-echoing sibling" {
        withBrainSync { coordinator, storage, _ ->
            storage.files["notes/a.md"] = "base".encodeToByteArray()
            coordinator.captureChanges()
            storage.files["notes/a.md"] = "local edit".encodeToByteArray()
            val deletion = tombstone(1, "notes/a.md", ContentHash.sha256("base".encodeToByteArray()))

            coordinator.applyIncoming(deletion, null) shouldBe ConflictOutcome.CONFLICT_PRESERVED
            storage.files["notes/a.md"]!!.decodeToString() shouldBe "local edit"
            val sibling = storage.files.keys.single { it.contains(".sync-conflict-") }
            storage.files[sibling]!!.decodeToString() shouldBe "local edit"

            coordinator.applyIncoming(deletion, null) shouldBe ConflictOutcome.CONFLICT_PRESERVED
            storage.files.keys.count { it.contains(".sync-conflict-") } shouldBe 1
            coordinator.captureChanges().single().target shouldBe "notes/a.md"
            coordinator.captureChanges() shouldBe emptyList()
        }
    }

    "incoming operations reject audio, absolute paths, and mismatched image content" {
        withBrainSync { coordinator, _, _ ->
            listOf(
                snapshot(1, "meetings/android-bridge/audio.m4a", "audio", null, "audio/mp4"),
                snapshot(1, "/notes/a.md", "text", null),
                snapshot(1, "meetings/android-bridge/photo.jpg", "text", null, "image/jpeg"),
            ).forEach { operation ->
                runCatching { coordinator.applyIncoming(operation, operationBytes(operation)) }.isFailure shouldBe true
            }
        }
    }

    "relay snapshot callback runs before durable acknowledgement and duplicate delivery is a no-op" {
        val senderRoot = Files.createTempDirectory("brain-relay-sender").toFile()
        val receiverRoot = Files.createTempDirectory("brain-relay-receiver").toFile()
        try {
            val senderJournal = DurableSyncJournal(senderRoot, "mac")
            senderJournal.enqueue("snapshot-1", SyncOperationKind.SNAPSHOT, "notes/a.md", "hello".encodeToByteArray(), mediaType = "text/markdown")
            val applied = mutableListOf<String>()
            val receiverJournal = DurableSyncJournal(receiverRoot, "phone")
            val receiver = AndroidRelayReplaySession(
                receiverJournal,
                "phone",
                "mac",
                syncOperationApplier = { operation, bytes -> applied += "${operation.target}:${bytes!!.decodeToString()}" },
            )
            val operationFrames = AndroidRelayReplaySession(senderJournal, "mac", "phone").sessionFrames()
                .map(MessageCodec::decode)
                .filter { it.type == MessageTypes.SYNC_OPERATION || it.type == MessageTypes.SYNC_TRANSFER_CHUNK }

            receiver.handle(operationFrames.first()).outboundFrames shouldBe emptyList()
            receiverJournal.receivedThrough("mac") shouldBe 0
            val completed = receiver.handle(operationFrames.last())
            applied shouldBe listOf("notes/a.md:hello")
            receiverJournal.receivedThrough("mac") shouldBe 1
            completed.outboundFrames.single().acknowledgement().cursor.throughSequence shouldBe 1

            val duplicate = receiver.handle(operationFrames.first())
            applied shouldBe listOf("notes/a.md:hello")
            duplicate.outboundFrames.single().acknowledgement().operationId shouldBe "snapshot-1"
        } finally {
            senderRoot.deleteRecursively()
            receiverRoot.deleteRecursively()
        }
    }

    "relay chunks a durable message larger than the control-frame limit" {
        val senderRoot = Files.createTempDirectory("relay-message-sender").toFile()
        val receiverRoot = Files.createTempDirectory("relay-message-receiver").toFile()
        try {
            val sender = AndroidRelayReplaySession(DurableSyncJournal(senderRoot, "phone"), "phone", "mac")
            val delivered = mutableListOf<Message>()
            val receiver = AndroidRelayReplaySession(
                DurableSyncJournal(receiverRoot, "mac"),
                "mac",
                "phone",
                messageApplier = delivered::add,
            )
            val payload = "x".repeat(1_200_000)
            val message = Message("large-message", MessageTypes.MEETING_PHOTO_OFFER, payload = buildJsonObject { put("data", payload) })

            sender.enqueue(message).map(MessageCodec::decode).forEach(receiver::handle)

            delivered.single() shouldBe message
        } finally {
            senderRoot.deleteRecursively()
            receiverRoot.deleteRecursively()
        }
    }

    "relay rejects chunks beyond the operation declared byte count" {
        val root = Files.createTempDirectory("relay-chunk-limit").toFile()
        try {
            val bytes = byteArrayOf(1, 2)
            val digest = ContentHash.sha256(bytes)
            val operation = SyncOperation(
                "oversized-chunk",
                "mac",
                1,
                SyncOperationKind.SNAPSHOT,
                "notes/a.md",
                resultDigest = digest,
                blobDigest = digest,
                byteCount = 1,
                mediaType = "text/markdown",
            )
            val receiver = AndroidRelayReplaySession(
                DurableSyncJournal(root, "phone"),
                "phone",
                "mac",
                syncOperationApplier = { _, _ -> },
            )
            receiver.handle(syncOperationMessage(operation))
            val chunk = TransferChunk("oversized-chunk", 0, 0, Base64.getEncoder().encodeToString(bytes), digest, true)

            runCatching { receiver.handle(syncMessage(MessageTypes.SYNC_TRANSFER_CHUNK, chunk)) }.isFailure shouldBe true
        } finally {
            root.deleteRecursively()
        }
    }

    "relay message callback failure leaves cursor unchanged" {
        val senderRoot = Files.createTempDirectory("relay-message-failure-sender").toFile()
        val receiverRoot = Files.createTempDirectory("relay-message-failure-receiver").toFile()
        try {
            val sender = AndroidRelayReplaySession(DurableSyncJournal(senderRoot, "phone"), "phone", "mac")
            val receiverJournal = DurableSyncJournal(receiverRoot, "mac")
            val receiver = AndroidRelayReplaySession(
                receiverJournal,
                "mac",
                "phone",
                messageApplier = { error("disk failed") },
            )
            val frames = sender.enqueue(Message("message-failure", MessageTypes.SMS_RECEIVED)).map(MessageCodec::decode)

            receiver.handle(frames.first())
            runCatching { receiver.handle(frames.last()) }.isFailure shouldBe true
            receiverJournal.receivedThrough("phone") shouldBe 0
        } finally {
            senderRoot.deleteRecursively()
            receiverRoot.deleteRecursively()
        }
    }

    "relay tombstone acknowledges only after callback and callback failure leaves cursor unchanged" {
        val root = Files.createTempDirectory("brain-relay-tombstone").toFile()
        try {
            val journal = DurableSyncJournal(root, "phone")
            val operation = SyncOperation("delete-1", "mac", 1, SyncOperationKind.TOMBSTONE, "notes/a.md", baseDigest = "a".repeat(64))
            val message = syncOperationMessage(operation)
            val failing = AndroidRelayReplaySession(
                journal,
                "phone",
                "mac",
                syncOperationApplier = { _, _ -> error("disk failed") },
            )
            runCatching { failing.handle(message) }.isFailure shouldBe true
            journal.receivedThrough("mac") shouldBe 0

            var deleted = false
            val succeeding = AndroidRelayReplaySession(
                journal,
                "phone",
                "mac",
                syncOperationApplier = { _, bytes ->
                    bytes shouldBe null
                    deleted = true
                },
            )
            val result = succeeding.handle(message)
            deleted shouldBe true
            journal.receivedThrough("mac") shouldBe 1
            result.outboundFrames.single().acknowledgement().operationId shouldBe "delete-1"
        } finally {
            root.deleteRecursively()
        }
    }
})

private class FakeBrainSyncStorage : BrainSyncStorage {
    val files = linkedMapOf<String, ByteArray>()
    override fun files(): List<BrainSyncFile> = files.map { BrainSyncFile(it.key, it.value) }
    override fun read(path: String): ByteArray? = files[path]
    override fun write(path: String, bytes: ByteArray) { files[path] = bytes }
    override fun delete(path: String) { files.remove(path) }
}

private suspend fun withBrainSync(block: suspend (BrainSyncCoordinator, FakeBrainSyncStorage, DurableSyncJournal) -> Unit) {
    val root = Files.createTempDirectory("brain-sync").toFile()
    try {
        val storage = FakeBrainSyncStorage()
        val journal = DurableSyncJournal(Files.createDirectories(root.toPath().resolve("journal")).toFile(), "phone")
        val manifest = BrainSyncManifest(root.resolve("manifest.json"))
        block(BrainSyncCoordinator(journal, manifest, storage), storage, journal)
    } finally {
        root.deleteRecursively()
    }
}

private fun snapshot(sequence: Long, path: String, content: String, base: String?, mediaType: String = "text/markdown"): SyncOperation {
    val bytes = content.encodeToByteArray()
    val digest = ContentHash.sha256(bytes)
    return SyncOperation(
        operationId = "remote-$sequence-${digest.take(8)}",
        actorId = "mac",
        sequence = sequence,
        kind = SyncOperationKind.SNAPSHOT,
        target = path,
        baseDigest = base,
        resultDigest = digest,
        blobDigest = digest,
        byteCount = bytes.size.toLong(),
        mediaType = mediaType,
    )
}

private fun tombstone(sequence: Long, path: String, base: String) = SyncOperation(
    operationId = "remote-delete-$sequence",
    actorId = "mac",
    sequence = sequence,
    kind = SyncOperationKind.TOMBSTONE,
    target = path,
    baseDigest = base,
)

private fun operationBytes(operation: SyncOperation): ByteArray = when (operation.target.substringAfterLast('.')) {
    "jpg" -> "text".encodeToByteArray()
    else -> operation.resultDigest?.let { "text".encodeToByteArray() } ?: ByteArray(0)
}

private fun jpeg(): ByteArray = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 1, 0xff.toByte(), 0xd9.toByte())
private fun png(): ByteArray = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1)

private fun syncOperationMessage(operation: SyncOperation) = com.androidbridge.protocol.Message(
    id = "frame-${operation.operationId}",
    type = MessageTypes.SYNC_OPERATION,
    payload = SyncModelCodec.json.encodeToJsonElement(SyncOperation.serializer(), operation) as kotlinx.serialization.json.JsonObject,
)

private inline fun <reified T> syncMessage(type: String, model: T) = com.androidbridge.protocol.Message(
    id = "frame-${java.util.UUID.randomUUID()}",
    type = type,
    payload = SyncModelCodec.json.encodeToJsonElement(model) as kotlinx.serialization.json.JsonObject,
)

private fun ByteArray.acknowledgement(): SyncAcknowledgement {
    val message = MessageCodec.decode(this)
    return SyncModelCodec.json.decodeFromJsonElement(message.payload)
}
