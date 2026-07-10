package com.androidbridge.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/** Protocol constants — see protocol/PROTOCOL.md §9. */
const val PROTOCOL_VERSION: Int = 1
const val MAX_CONTROL_BYTES: Long = 1_048_576 // 1 MiB
const val DEFAULT_CHUNK_BYTES: Int = 65_536 // 64 KiB
const val INLINE_BLOB_MAX_BYTES: Int = 32_768 // 32 KiB
const val FLAG_END_OF_STREAM: Int = 0x01
const val FRAME_HEADER_BYTES: Int = 13

/** Control message envelope — PROTOCOL.md §2. */
@Serializable
data class Message(
    val id: String,
    val type: String,
    val protocolVersion: Int = PROTOCOL_VERSION,
    val replyTo: String? = null,
    val payload: JsonObject = JsonObject(emptyMap()),
)

/** Binary frame header — PROTOCOL.md §5. `streamId`/`sequence` are unsigned 32-bit (held in Long). */
data class FrameHeader(
    val streamId: Long,
    val sequence: Long,
    val length: Int,
    val flags: Int,
) {
    val isEndOfStream: Boolean get() = (flags and FLAG_END_OF_STREAM) != 0
}

/** A framed chunk. Custom equality so `payload` compares by content (needed for round-trip PBT). */
class Frame(val header: FrameHeader, val payload: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is Frame && header == other.header && payload.contentEquals(other.payload)

    override fun hashCode(): Int = 31 * header.hashCode() + payload.contentHashCode()

    override fun toString(): String = "Frame(header=$header, payload=${payload.size} bytes)"
}

/** Typed protocol failures — PROTOCOL.md §4. Carries no payload content (CC-PRIV / SECURITY-03). */
enum class ProtocolErrorCode {
    MALFORMED_LENGTH,
    MALFORMED_JSON,
    OVERSIZE,
    UNKNOWN_TYPE,
    SCHEMA_MISMATCH,
    BAD_FRAME_HEADER,
    VERSION_MISMATCH,
}

class ProtocolException(val code: ProtocolErrorCode) : Exception(code.name)

/** Result of validating an inbound message. */
data class ValidationResult(val valid: Boolean, val code: ProtocolErrorCode? = null) {
    companion object {
        val OK = ValidationResult(true)
        fun fail(code: ProtocolErrorCode) = ValidationResult(false, code)
    }
}

/** Message type registry — PROTOCOL.md §6. Single source of truth for valid control types. */
object MessageTypes {
    const val LINK_HELLO = "link.hello"
    const val LINK_HEARTBEAT = "link.heartbeat"
    const val PAIR_REQUEST = "pair.request"
    const val PAIR_RESPONSE = "pair.response"
    const val NOTIF_POSTED = "notif.posted"
    const val SMS_RECEIVED = "sms.received"
    const val SMS_THREAD = "sms.thread"
    const val FILE_OFFER = "file.offer"
    const val FILE_ACCEPT = "file.accept"
    const val FILE_PROGRESS = "file.progress"
    const val FILE_CHUNK = "file.chunk"
    const val CLIP_UPDATE = "clip.update"
    const val SCREEN_START = "screen.start"
    const val SCREEN_STOP = "screen.stop"
    const val SCREEN_FRAME = "screen.frame"
    const val SCREEN_REQUEST = "screen.request"
    const val INPUT_TAP = "input.tap"
    const val INPUT_SWIPE = "input.swipe"
    const val CALL_INCOMING = "call.incoming"
    const val CALL_ACTION = "call.action"
    const val CALL_STATE = "call.state"
    const val CALL_HISTORY = "call.history"
    const val MEETING_START = "meeting.start"
    const val MEETING_STOP = "meeting.stop"
    const val MEETING_AUDIO_CHUNK_OFFER = "meeting.audioChunk.offer"
    const val MEETING_AUDIO_CHUNK_RECEIVED = "meeting.audioChunk.received"
    const val MEETING_PHOTO_OFFER = "meeting.photo.offer"
    const val MEETING_PHOTO_RECEIVED = "meeting.photo.received"
    const val MEETING_PROCESSING_STATUS = "meeting.processing.status"
    const val MEETING_NOTES_READY = "meeting.notes.ready"

    val known: Set<String> = setOf(
        LINK_HELLO, LINK_HEARTBEAT, PAIR_REQUEST, PAIR_RESPONSE,
        NOTIF_POSTED, SMS_RECEIVED, SMS_THREAD,
        FILE_OFFER, FILE_ACCEPT, FILE_PROGRESS, FILE_CHUNK,
        CLIP_UPDATE, SCREEN_START, SCREEN_STOP, SCREEN_FRAME, SCREEN_REQUEST,
        INPUT_TAP, INPUT_SWIPE, CALL_INCOMING, CALL_ACTION, CALL_STATE, CALL_HISTORY,
        MEETING_START, MEETING_STOP, MEETING_AUDIO_CHUNK_OFFER, MEETING_AUDIO_CHUNK_RECEIVED,
        MEETING_PHOTO_OFFER, MEETING_PHOTO_RECEIVED, MEETING_PROCESSING_STATUS, MEETING_NOTES_READY,
    )
}
