package com.androidbridge.protocol

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.Codepoint
import io.kotest.property.arbitrary.az
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.string
import io.kotest.property.checkAll
import java.util.Base64

private val syncOperationArb = Arb.bind(
    Arb.string(1..20, Codepoint.az()),
    Arb.string(1..20, Codepoint.az()),
    Arb.long(1, 100_000),
    Arb.element(SyncOperationKind.entries),
    Arb.string(1..30, Codepoint.az()),
) { operationId, actorId, sequence, kind, target ->
    SyncOperation(
        operationId = operationId,
        actorId = actorId,
        sequence = sequence,
        kind = kind,
        target = target,
        messageType = if (kind == SyncOperationKind.MESSAGE) MessageTypes.NOTIF_POSTED else null,
        resultDigest = if (kind == SyncOperationKind.TOMBSTONE) null else "a".repeat(64),
        blobDigest = if (kind == SyncOperationKind.TOMBSTONE) null else "a".repeat(64),
        byteCount = if (kind == SyncOperationKind.TOMBSTONE) 0 else 12,
        mediaType = if (kind == SyncOperationKind.TOMBSTONE) null else "application/octet-stream",
    )
}

class SyncProtocolTest : StringSpec({
    "sync model codecs round-trip capabilities, resume, acknowledgements, operations, and chunks" {
        val cursor = SyncCursor("phone", 41)
        val capabilities = CapabilityAnnouncement("phone", SyncCapability.entries)
        val resume = ResumeRequest(cursor)
        val acknowledgement = SyncAcknowledgement(cursor, "op-41")
        val operation = SyncOperation("op-42", "phone", 42, SyncOperationKind.SNAPSHOT, "notes/a.md", baseDigest = "b", resultDigest = "r", blobDigest = "r", byteCount = 3, mediaType = "text/markdown")
        val chunk = TransferChunk("op-42", 0, 0, Base64.getEncoder().encodeToString(byteArrayOf(1, 2, 3)), "digest", true)

        SyncModelCodec.decode<CapabilityAnnouncement>(SyncModelCodec.encode(capabilities)) shouldBe capabilities
        SyncModelCodec.decode<ResumeRequest>(SyncModelCodec.encode(resume)) shouldBe resume
        SyncModelCodec.decode<SyncAcknowledgement>(SyncModelCodec.encode(acknowledgement)) shouldBe acknowledgement
        SyncModelCodec.decode<SyncOperation>(SyncModelCodec.encode(operation)) shouldBe operation
        SyncModelCodec.decode<TransferChunk>(SyncModelCodec.encode(chunk)) shouldBe chunk
    }

    "PBT: immutable sync operations round-trip" {
        checkAll(syncOperationArb) { operation ->
            SyncModelCodec.decode<SyncOperation>(SyncModelCodec.encode(operation)) shouldBe operation
        }
    }

    "PBT: cursors advance monotonically and reject regression" {
        checkAll(Arb.long(0, 100_000), Arb.long(0, 100_000)) { current, increment ->
            val cursor = SyncCursor("mac", current)
            cursor.advancedTo(current + increment).throughSequence shouldBe current + increment
            if (current > 0) shouldThrow<IllegalArgumentException> { cursor.advancedTo(current - 1) }
        }
    }

    "replay classification is explicit" {
        ReplayClassifier.classify(MessageTypes.SMS_RECEIVED) shouldBe ReplayClassification.DURABLE
        ReplayClassifier.classify(MessageTypes.CLIP_UPDATE) shouldBe ReplayClassification.COALESCED
        ReplayClassifier.classify(MessageTypes.CALL_ACTION) shouldBe ReplayClassification.LIVE_ONLY
        ReplayClassifier.classify(MessageTypes.SCREEN_FRAME) shouldBe ReplayClassification.LIVE_ONLY
        MessageTypes.known.forEach { ReplayClassifier.classify(it) }
        MessageTypes.known.containsAll(MessageTypes.sync) shouldBe true
    }

    "PBT: truncated binary frames fail closed" {
        checkAll(Arb.int(1, MAX_FRAME_PAYLOAD_BYTES.toInt())) { declared ->
            val bytes = ByteArray(FRAME_HEADER_BYTES)
            writeU32BE(bytes, 8, declared.toLong())
            shouldThrow<ProtocolException> { FrameCodec.decodeFrame(bytes) }.code shouldBe ProtocolErrorCode.BAD_FRAME_HEADER
        }
    }

    "binary frame declared size is rejected before payload extraction" {
        checkAll(Arb.int(1, 10_000)) { extra ->
            val bytes = ByteArray(FRAME_HEADER_BYTES)
            writeU32BE(bytes, 8, MAX_FRAME_PAYLOAD_BYTES + extra.toLong())
            shouldThrow<ProtocolException> { FrameCodec.decodeFrame(bytes) }.code shouldBe ProtocolErrorCode.OVERSIZE
        }
    }

    "stream decoder rejects an oversized declaration from the four-byte header" {
        val decoder = ControlStreamDecoder()
        val header = ByteArray(4)
        writeU32BE(header, 0, MAX_CONTROL_BYTES + 1)
        shouldThrow<ProtocolException> { decoder.ingest(header) }.code shouldBe ProtocolErrorCode.OVERSIZE
        decoder.bufferedByteCount shouldBe 0
    }

    "PBT: stream decoder accepts arbitrary receive fragmentation" {
        checkAll(Arb.int(1, 32)) { fragmentSize ->
            val message = Message("fragmented", MessageTypes.SYNC_CAPABILITIES)
            val encoded = MessageCodec.encode(message)
            val decoder = ControlStreamDecoder()
            val decoded = encoded.asList().chunked(fragmentSize).flatMap { decoder.ingest(it.toByteArray()) }
            decoded shouldBe listOf(message)
            decoder.bufferedByteCount shouldBe 0
        }
    }
})
