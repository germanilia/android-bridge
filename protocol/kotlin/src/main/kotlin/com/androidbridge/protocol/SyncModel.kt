package com.androidbridge.protocol

import java.util.Base64
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
enum class SyncCapability {
    @SerialName("durable-sync-v1") DURABLE_SYNC,
    @SerialName("resumable-transfer-v1") RESUMABLE_TRANSFER,
    @SerialName("note-conflicts-v1") NOTE_CONFLICTS,
}

@Serializable
data class CapabilityAnnouncement(
    val actorId: String,
    val capabilities: List<SyncCapability>,
)

@Serializable
data class SyncCursor(val actorId: String, val throughSequence: Long) {
    init {
        require(actorId.isNotEmpty())
        require(throughSequence >= 0)
    }

    fun advancedTo(sequence: Long): SyncCursor {
        require(sequence >= throughSequence) { "cursor cannot move backward" }
        return copy(throughSequence = sequence)
    }
}

@Serializable
data class ResumeRequest(val cursor: SyncCursor)

@Serializable
data class SyncAcknowledgement(
    val cursor: SyncCursor,
    val operationId: String,
)

@Serializable
enum class SyncOperationKind {
    @SerialName("message") MESSAGE,
    @SerialName("snapshot") SNAPSHOT,
    @SerialName("tombstone") TOMBSTONE,
    @SerialName("transfer") TRANSFER,
}

@Serializable
data class SyncOperation(
    val operationId: String,
    val actorId: String,
    val sequence: Long,
    val kind: SyncOperationKind,
    val target: String,
    val messageType: String? = null,
    val baseDigest: String? = null,
    val resultDigest: String? = null,
    val blobDigest: String? = null,
    val byteCount: Long = 0,
    val mediaType: String? = null,
)

@Serializable
enum class ConflictOutcome {
    @SerialName("unchanged") UNCHANGED,
    @SerialName("applied") APPLIED,
    @SerialName("deleted") DELETED,
    @SerialName("conflictPreserved") CONFLICT_PRESERVED,
}

@Serializable
data class TransferChunk(
    val operationId: String,
    val index: Int,
    val offset: Long,
    val dataBase64: String,
    val digest: String,
    val isFinal: Boolean,
) {
    fun decodedData(): ByteArray = Base64.getDecoder().decode(dataBase64)
}

object SyncModelCodec {
    val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = false
        isLenient = false
    }

    inline fun <reified T> encode(value: T): String = json.encodeToString(value)
    inline fun <reified T> decode(value: String): T = json.decodeFromString(value)
}

@Serializable
enum class ReplayClassification {
    @SerialName("durable") DURABLE,
    @SerialName("coalesced") COALESCED,
    @SerialName("liveOnly") LIVE_ONLY,
}

object ReplayClassifier {
    private val durable = setOf(
        MessageTypes.NOTIF_POSTED,
        MessageTypes.SMS_RECEIVED,
        MessageTypes.SMS_THREAD,
        MessageTypes.FILE_OFFER,
        MessageTypes.FILE_PROGRESS,
        MessageTypes.FILE_CHUNK,
        MessageTypes.MEETING_START,
        MessageTypes.MEETING_STOP,
        MessageTypes.MEETING_AUDIO_CHUNK_OFFER,
        MessageTypes.MEETING_PHOTO_OFFER,
        MessageTypes.MEETING_PROCESSING_STATUS,
        MessageTypes.MEETING_NOTES_READY,
    )
    private val coalesced = setOf(MessageTypes.CLIP_UPDATE, MessageTypes.CALL_STATE)
    private val liveOnly = setOf(
        MessageTypes.LINK_HELLO,
        MessageTypes.LINK_HEARTBEAT,
        MessageTypes.PAIR_REQUEST,
        MessageTypes.PAIR_RESPONSE,
        MessageTypes.FILE_ACCEPT,
        MessageTypes.SCREEN_START,
        MessageTypes.SCREEN_STOP,
        MessageTypes.SCREEN_FRAME,
        MessageTypes.SCREEN_REQUEST,
        MessageTypes.INPUT_TAP,
        MessageTypes.INPUT_SWIPE,
        MessageTypes.CALL_INCOMING,
        MessageTypes.CALL_ACTION,
        MessageTypes.CALL_HISTORY,
        MessageTypes.MEETING_AUDIO_CHUNK_RECEIVED,
        MessageTypes.MEETING_PHOTO_RECEIVED,
    ) + MessageTypes.sync

    fun classify(messageType: String): ReplayClassification {
        if (messageType !in MessageTypes.known) throw ProtocolException(ProtocolErrorCode.UNKNOWN_TYPE)
        return when (messageType) {
            in durable -> ReplayClassification.DURABLE
            in coalesced -> ReplayClassification.COALESCED
            in liveOnly -> ReplayClassification.LIVE_ONLY
            else -> throw ProtocolException(ProtocolErrorCode.SCHEMA_MISMATCH)
        }
    }
}
