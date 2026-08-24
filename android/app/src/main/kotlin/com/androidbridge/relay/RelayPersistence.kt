package com.androidbridge.relay

import com.androidbridge.protocol.MAX_CONTROL_BYTES
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Base64

@Serializable
data class SpoolRef(val sha256: String, val size: Long)

@Serializable
data class JournalEntry(
    val actor: String,
    val sequence: Long,
    val operationId: String,
    val messageType: String,
    val replayClass: ReplayClass,
    val payloadBase64: String,
    val spool: SpoolRef? = null,
) {
    fun payload(): ByteArray = Base64.getDecoder().decode(payloadBase64)
}

class RelayJournal(private val directory: File, private val actor: String, private val json: Json = Json) {
    private val journalFile = File(directory, "journal-$actor.jsonl")
    private val ackFile = File(directory, "ack-$actor")
    private val entries = ArrayList<JournalEntry>()

    init {
        require(actor.matches(Regex("[A-Za-z0-9._:-]{1,128}"))) { "Invalid journal actor" }
        directory.mkdirs()
        if (journalFile.exists()) journalFile.useLines { lines ->
            lines.filter(String::isNotBlank).mapTo(entries) { json.decodeFromString(JournalEntry.serializer(), it) }
        }
        require(acknowledgedSequence <= highWaterSequence) { "Acknowledgement exceeds persisted journal" }
    }

    val highWaterSequence: Long get() = entries.lastOrNull()?.sequence ?: 0
    val acknowledgedSequence: Long get() = if (ackFile.exists()) ackFile.readText().toLong() else 0

    @Synchronized
    fun append(
        operationId: String,
        messageType: String,
        replayClass: ReplayClass,
        payload: ByteArray,
        spool: SpoolRef? = null,
    ): JournalEntry {
        require(operationId.length in 1..128 && messageType.length in 1..128)
        require(replayClass != ReplayClass.LIVE_ONLY)
        require(payload.size <= MAX_CONTROL_BYTES)
        val entry = JournalEntry(actor, highWaterSequence + 1, operationId, messageType, replayClass, Base64.getEncoder().encodeToString(payload), spool)
        appendLine(json.encodeToString(JournalEntry.serializer(), entry))
        entries.add(entry)
        return entry
    }

    @Synchronized
    fun acknowledge(sequence: Long): List<JournalEntry> {
        val previous = acknowledgedSequence
        require(sequence >= previous) { "Acknowledgement moved backward" }
        require(sequence <= highWaterSequence) { "Acknowledgement exceeds high-water mark" }
        atomicWrite(ackFile, sequence.toString())
        return entries.filter { it.sequence in (previous + 1)..sequence }
    }

    @Synchronized
    fun pending(): List<JournalEntry> {
        val unacknowledged = entries.filter { it.sequence > acknowledgedSequence }
        val latestCoalesced = unacknowledged.filter { it.replayClass == ReplayClass.COALESCING }
            .groupBy(JournalEntry::messageType).mapValues { (_, values) -> values.maxOf(JournalEntry::sequence) }
        return unacknowledged.filter { it.replayClass != ReplayClass.COALESCING || latestCoalesced[it.messageType] == it.sequence }
    }

    private fun appendLine(line: String) {
        FileOutputStream(journalFile, true).use { output ->
            output.write(line.encodeToByteArray())
            output.write('\n'.code)
            output.fd.sync()
        }
    }
}

class RelayResumeController(private val journal: RelayJournal) {
    @Synchronized
    fun resume(peerCursor: Long): List<JournalEntry> {
        journal.acknowledge(peerCursor)
        return journal.pending()
    }

    @Synchronized
    fun acknowledge(peerCursor: Long) {
        journal.acknowledge(peerCursor)
    }
}

class RelaySpool(private val directory: File) {
    init { directory.mkdirs() }

    fun put(bytes: ByteArray): SpoolRef = put(bytes.inputStream())

    @Synchronized
    fun put(input: InputStream): SpoolRef {
        val temporary = File.createTempFile("relay-", ".tmp", directory)
        val digest = MessageDigest.getInstance("SHA-256")
        var size = 0L
        input.use { source -> temporary.outputStream().use { output ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = source.read(buffer)
                if (read < 0) break
                if (read == 0) continue
                output.write(buffer, 0, read)
                digest.update(buffer, 0, read)
                size += read
            }
            output.fd.sync()
        } }
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        val target = file(hash)
        if (target.exists()) {
            temporary.delete()
        } else {
            try {
                Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
            } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                Files.move(temporary.toPath(), target.toPath())
            }
        }
        return SpoolRef(hash, size)
    }

    fun read(sha256: String): ByteArray = file(sha256).readBytes()
    fun open(sha256: String): InputStream = file(sha256).inputStream()
    fun contains(sha256: String): Boolean = file(sha256).isFile
    fun delete(sha256: String): Boolean = file(sha256).delete()

    private fun file(sha256: String): File {
        require(sha256.matches(Regex("[0-9a-f]{64}"))) { "Invalid spool digest" }
        return File(directory, sha256)
    }
}

data class PendingDurablePayload(
    val operationId: String,
    val messageType: String,
    val metadata: ByteArray,
    val ownedBytes: InputStream? = null,
)

/** Brain/file model adapters can target this without coupling Android storage to protocol models. */
fun interface RelayDurableOperationSink {
    fun enqueue(payload: PendingDurablePayload): JournalEntry
}

class AppPrivateRelayStore(filesDir: File, actor: String) : RelayDurableOperationSink {
    val root = File(filesDir, "relay")
    val journal = RelayJournal(File(root, "journal"), actor)
    val spool = RelaySpool(File(root, "spool"))

    override fun enqueue(payload: PendingDurablePayload): JournalEntry {
        val replayClass = ReplayClassifier.classify(payload.messageType)
        require(replayClass != ReplayClass.LIVE_ONLY) { "Live-only messages cannot enter durable storage" }
        val spoolRef = payload.ownedBytes?.let(spool::put)
        if (replayClass == ReplayClass.SPOOLED) require(spoolRef != null) { "Spooled message requires owned bytes" }
        return journal.append(payload.operationId, payload.messageType, replayClass, payload.metadata, spoolRef)
    }

    fun acknowledge(sequence: Long) {
        val acknowledged = journal.acknowledge(sequence)
        val retainedHashes = journal.pending().mapNotNull { it.spool?.sha256 }.toSet()
        acknowledged.mapNotNull { it.spool?.sha256 }.filterNot(retainedHashes::contains).forEach(spool::delete)
    }
}
