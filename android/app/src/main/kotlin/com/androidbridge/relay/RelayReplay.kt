package com.androidbridge.relay

import com.androidbridge.protocol.MessageTypes
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

enum class ReplayClass { LIVE_ONLY, REPLAY_SAFE, COALESCING, SPOOLED }

object ReplayClassifier {
    fun classify(type: String): ReplayClass = when (type) {
        MessageTypes.CLIP_UPDATE -> ReplayClass.COALESCING
        MessageTypes.FILE_CHUNK,
        MessageTypes.MEETING_PHOTO_OFFER,
        MessageTypes.MEETING_AUDIO_CHUNK_OFFER -> ReplayClass.SPOOLED
        MessageTypes.NOTIF_POSTED,
        MessageTypes.SMS_RECEIVED,
        MessageTypes.SMS_THREAD,
        MessageTypes.FILE_OFFER,
        MessageTypes.FILE_ACCEPT,
        MessageTypes.FILE_PROGRESS,
        MessageTypes.CALL_STATE,
        MessageTypes.CALL_HISTORY,
        MessageTypes.MEETING_PHOTO_RECEIVED,
        MessageTypes.MEETING_AUDIO_CHUNK_RECEIVED,
        MessageTypes.MEETING_PROCESSING_STATUS,
        MessageTypes.MEETING_NOTES_READY -> ReplayClass.REPLAY_SAFE
        MessageTypes.LINK_HELLO,
        MessageTypes.LINK_HEARTBEAT,
        MessageTypes.PAIR_REQUEST,
        MessageTypes.PAIR_RESPONSE,
        MessageTypes.SCREEN_START,
        MessageTypes.SCREEN_STOP,
        MessageTypes.SCREEN_FRAME,
        MessageTypes.SCREEN_REQUEST,
        MessageTypes.INPUT_TAP,
        MessageTypes.INPUT_SWIPE,
        MessageTypes.CALL_INCOMING,
        MessageTypes.CALL_ACTION,
        MessageTypes.MEETING_START,
        MessageTypes.MEETING_STOP -> ReplayClass.LIVE_ONLY
        else -> throw IllegalArgumentException("Unclassified message type: $type")
    }
}

enum class ReceiveDecision { APPLY, DUPLICATE, OUT_OF_ORDER }

@Serializable
private data class ReceiveState(val cursor: Long = 0, val operationIds: Set<String> = emptySet())

class ResumeReceiver(private val directory: File, private val json: Json = Json) {
    private val stateFile = File(directory, "receive-state.json")
    private var state: ReceiveState

    init {
        directory.mkdirs()
        state = if (stateFile.exists()) json.decodeFromString(ReceiveState.serializer(), stateFile.readText()) else ReceiveState()
    }

    val cursor: Long get() = state.cursor

    @Synchronized
    fun classify(sequence: Long, operationId: String): ReceiveDecision {
        require(sequence > 0 && operationId.length in 1..128)
        if (sequence <= state.cursor) return ReceiveDecision.DUPLICATE
        if (sequence != state.cursor + 1) return ReceiveDecision.OUT_OF_ORDER
        return if (operationId in state.operationIds) ReceiveDecision.DUPLICATE else ReceiveDecision.APPLY
    }

    @Synchronized
    fun commit(sequence: Long, operationId: String) {
        require(sequence == state.cursor + 1)
        require(classify(sequence, operationId) != ReceiveDecision.OUT_OF_ORDER)
        state = ReceiveState(sequence, state.operationIds + operationId)
        atomicWrite(stateFile, json.encodeToString(ReceiveState.serializer(), state))
    }
}

internal fun atomicWrite(target: File, content: String) {
    target.parentFile?.mkdirs()
    val temporary = File(target.parentFile, ".${target.name}.tmp")
    temporary.outputStream().use { output ->
        output.write(content.encodeToByteArray())
        output.fd.sync()
    }
    try {
        Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
        Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
    }
}
