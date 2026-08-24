package com.androidbridge

import com.androidbridge.core.BoundedControlReader
import com.androidbridge.core.ContentHash
import com.androidbridge.core.DurableSyncJournal
import com.androidbridge.core.IncomingDisposition
import com.androidbridge.core.NoteConflictResolver
import com.androidbridge.core.SyncJournalError
import com.androidbridge.core.SyncJournalException
import com.androidbridge.core.migrateDurableSyncJournal
import com.androidbridge.core.SyncTransferChunker
import com.androidbridge.core.SyncTransferReassembler
import com.androidbridge.protocol.ConflictOutcome
import com.androidbridge.protocol.MAX_CONTROL_BYTES
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import com.androidbridge.protocol.MessageTypes
import com.androidbridge.protocol.ProtocolErrorCode
import com.androidbridge.protocol.ProtocolException
import com.androidbridge.protocol.SyncOperation
import com.androidbridge.protocol.SyncModelCodec
import com.androidbridge.protocol.SyncOperationKind
import io.kotest.assertions.throwables.shouldThrow
import kotlinx.serialization.decodeFromString
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.byte
import io.kotest.property.arbitrary.byteArray
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.list
import io.kotest.property.checkAll
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.File
import java.nio.file.Files

class SyncJournalTest : StringSpec({
    "Android receive path rejects oversized control declarations before body allocation" {
        val header = byteArrayOf(
            ((MAX_CONTROL_BYTES + 1) ushr 24).toByte(),
            ((MAX_CONTROL_BYTES + 1) ushr 16).toByte(),
            ((MAX_CONTROL_BYTES + 1) ushr 8).toByte(),
            (MAX_CONTROL_BYTES + 1).toByte(),
        )
        shouldThrow<ProtocolException> {
            BoundedControlReader.read(DataInputStream(ByteArrayInputStream(header)))
        }.code shouldBe ProtocolErrorCode.OVERSIZE
    }

    "journal atomically persists immutable operations and owned content-addressed blobs" {
        val root = Files.createTempDirectory("android-bridge-journal").toFile()
        try {
            val bytes = "hello journal".encodeToByteArray()
            val journal = DurableSyncJournal(root, "phone")
            val operation = journal.enqueue("op-1", SyncOperationKind.SNAPSHOT, "notes/a.md", bytes, mediaType = "text/markdown")

            operation.sequence shouldBe 1
            operation.blobDigest shouldBe ContentHash.sha256(bytes)
            DurableSyncJournal(root, "phone").pending() shouldBe listOf(operation)
            DurableSyncJournal(root, "phone").readBlob(operation.blobDigest!!).toList() shouldBe bytes.toList()
        } finally {
            root.deleteRecursively()
        }
    }

    "legacy random-actor journal migrates pending media into role actor journal" {
        val root = Files.createTempDirectory("android-bridge-journal-migration").toFile()
        try {
            val legacyRoot = root.resolve("relay-sync")
            val currentRoot = root.resolve("relay-sync-v2")
            val message = Message("media-1", MessageTypes.MEETING_AUDIO_CHUNK_OFFER)
            val bytes = MessageCodec.encode(message)
            DurableSyncJournal(legacyRoot, "android-random").enqueue(
                "media-1",
                SyncOperationKind.MESSAGE,
                "media-1",
                bytes,
                messageType = MessageTypes.MEETING_AUDIO_CHUNK_OFFER,
            )

            val migrated = migrateDurableSyncJournal(legacyRoot, currentRoot, "android-random", "phone")

            migrated.pending().single().actorId shouldBe "phone"
            val migratedBytes = migrated.readBlob(migrated.pending().single().blobDigest!!)
            SyncModelCodec.json.decodeFromString<Message>(migratedBytes.decodeToString()) shouldBe message
            legacyRoot.exists() shouldBe false
        } finally {
            root.deleteRecursively()
        }
    }

    "acknowledgements are cumulative, monotonic, bounded, and resume returns the exact suffix" {
        val root = Files.createTempDirectory("android-bridge-journal").toFile()
        try {
            val journal = DurableSyncJournal(root, "phone")
            val operations = (1..5).map {
                journal.enqueue("op-$it", SyncOperationKind.MESSAGE, "event-$it", byteArrayOf(it.toByte()), messageType = "notif.posted")
            }

            journal.acknowledge(2)
            File(root, "blobs/${operations[0].blobDigest}").exists() shouldBe false
            File(root, "blobs/${operations[2].blobDigest}").exists() shouldBe true
            journal.pending().map { it.sequence } shouldBe listOf(3L, 4L, 5L)
            journal.pending(afterSequence = 3).map { it.sequence } shouldBe listOf(4L, 5L)
            shouldThrow<SyncJournalException> { journal.acknowledge(1) }.error shouldBe SyncJournalError.CURSOR_REGRESSION
            shouldThrow<SyncJournalException> { journal.acknowledge(6) }.error shouldBe SyncJournalError.CURSOR_BEYOND_HIGH_WATER
            shouldThrow<SyncJournalException> { journal.pending(afterSequence = 1) }.error shouldBe SyncJournalError.STALE_CURSOR
        } finally {
            root.deleteRecursively()
        }
    }

    "received operation IDs deduplicate without reapplying and sequence gaps fail closed" {
        val root = Files.createTempDirectory("android-bridge-journal").toFile()
        try {
            val journal = DurableSyncJournal(root, "phone")
            val first = remoteOperation("remote-1", 1)
            journal.incomingDisposition(first) shouldBe IncomingDisposition.APPLY
            journal.recordApplied(first) shouldBe true
            journal.incomingDisposition(first) shouldBe IncomingDisposition.DUPLICATE
            journal.recordApplied(first) shouldBe false
            journal.incomingDisposition(remoteOperation("remote-3", 3)) shouldBe IncomingDisposition.GAP
            DurableSyncJournal(root, "phone").receivedThrough("mac") shouldBe 1
        } finally {
            root.deleteRecursively()
        }
    }

    "content hashes drive no-op, apply, delete, and conflict preservation without clocks" {
        val base = "base".encodeToByteArray()
        val incoming = "incoming".encodeToByteArray()
        NoteConflictResolver.resolve(base, incoming, ContentHash.sha256(base)).outcome shouldBe ConflictOutcome.APPLIED
        NoteConflictResolver.resolve(incoming, incoming, ContentHash.sha256(base)).outcome shouldBe ConflictOutcome.UNCHANGED
        NoteConflictResolver.resolve(base, null, ContentHash.sha256(base)).outcome shouldBe ConflictOutcome.DELETED
        val conflict = NoteConflictResolver.resolve("local".encodeToByteArray(), incoming, ContentHash.sha256(base))
        conflict.outcome shouldBe ConflictOutcome.CONFLICT_PRESERVED
        conflict.canonical!!.decodeToString() shouldBe "local"
        conflict.conflict!!.decodeToString() shouldBe "incoming"
    }

    "transfer chunks are bounded, digest-verified, ordered, and byte exact" {
        val data = ByteArray(1000) { (it % 251).toByte() }
        val chunks = SyncTransferChunker.chunk("op", data, 128)
        chunks.all { it.decodedData().size <= 128 } shouldBe true
        val reassembler = SyncTransferReassembler("op", ContentHash.sha256(data))
        chunks.forEach { reassembler.accept(it) }
        reassembler.result().toList() shouldBe data.toList()
        val corrupted = chunks.first().copy(dataBase64 = java.util.Base64.getEncoder().encodeToString(byteArrayOf(9)))
        shouldThrow<SyncJournalException> { SyncTransferReassembler("op", ContentHash.sha256(data)).accept(corrupted) }
            .error shouldBe SyncJournalError.DIGEST_MISMATCH
    }

    "PBT: restart and resume preserve exactly the unacknowledged suffix" {
        checkAll(Arb.list(Arb.byteArray(Arb.int(0, 32), Arb.byte()), 1..20), Arb.int()) { payloads, selector ->
            val root = Files.createTempDirectory("android-bridge-journal-pbt").toFile()
            try {
                val journal = DurableSyncJournal(root, "phone")
                payloads.forEachIndexed { index, bytes ->
                    journal.enqueue("op-${index + 1}", SyncOperationKind.MESSAGE, "event-${index + 1}", bytes, messageType = "sms.received")
                }
                val acknowledged = Math.floorMod(selector, payloads.size + 1).toLong()
                journal.acknowledge(acknowledged)
                DurableSyncJournal(root, "phone").pending().map { it.sequence } shouldBe
                    ((acknowledged + 1)..payloads.size.toLong()).toList()
            } finally {
                root.deleteRecursively()
            }
        }
    }

    "PBT: duplicate delivery is idempotent" {
        checkAll(Arb.int(1, 40)) { count ->
            val root = Files.createTempDirectory("android-bridge-dedup-pbt").toFile()
            try {
                val journal = DurableSyncJournal(root, "phone")
                (1..count).forEach { sequence ->
                    val operation = remoteOperation("remote-$sequence", sequence.toLong())
                    journal.recordApplied(operation) shouldBe true
                    journal.recordApplied(operation) shouldBe false
                }
                journal.receivedThrough("mac") shouldBe count.toLong()
            } finally {
                root.deleteRecursively()
            }
        }
    }

    "PBT: conflict handling preserves both distinct byte sequences" {
        checkAll(
            Arb.byteArray(Arb.int(0, 64), Arb.byte()),
            Arb.byteArray(Arb.int(0, 64), Arb.byte()),
        ) { local, generatedIncoming ->
            val incoming = if (local.contentEquals(generatedIncoming)) generatedIncoming + 1 else generatedIncoming
            val resolution = NoteConflictResolver.resolve(local, incoming, ContentHash.sha256(local + 0))
            resolution.outcome shouldBe ConflictOutcome.CONFLICT_PRESERVED
            resolution.canonical!!.toList() shouldBe local.toList()
            resolution.conflict!!.toList() shouldBe incoming.toList()
        }
    }

    "PBT: chunk reassembly preserves arbitrary bytes" {
        checkAll(Arb.byteArray(Arb.int(0, 5000), Arb.byte()), Arb.int(1, 512)) { bytes, chunkSize ->
            val chunks = SyncTransferChunker.chunk("op", bytes, chunkSize)
            val reassembler = SyncTransferReassembler("op", ContentHash.sha256(bytes))
            chunks.forEach { reassembler.accept(it) }
            reassembler.result().toList() shouldBe bytes.toList()
        }
    }
})

private fun remoteOperation(id: String, sequence: Long) = SyncOperation(
    operationId = id,
    actorId = "mac",
    sequence = sequence,
    kind = SyncOperationKind.MESSAGE,
    target = "event-$sequence",
    messageType = "notif.posted",
    resultDigest = "a".repeat(64),
    blobDigest = "a".repeat(64),
    byteCount = 1,
)
