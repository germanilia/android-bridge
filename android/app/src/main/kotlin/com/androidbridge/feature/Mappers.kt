package com.androidbridge.feature

import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageTypes
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

/**
 * Pure mappers from OS-domain events to protocol [Message]s. Kept free of Android types so they are
 * JVM-testable; the Android plugins (NotificationListenerService, Telephony, InCallService) call
 * these after extracting plain values from the platform objects.
 */
object Mappers {

    fun notification(pkg: String, title: String, text: String, postedAt: Long): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.NOTIF_POSTED,
            payload = buildJsonObject {
                put("pkg", pkg); put("title", title); put("text", text); put("postedAt", postedAt)
            },
        )

    fun smsReceived(threadId: Long, address: String, body: String, receivedAt: Long): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.SMS_RECEIVED,
            payload = buildJsonObject {
                put("threadId", threadId); put("address", address); put("body", body); put("receivedAt", receivedAt)
            },
        )

    fun incomingCall(number: String, contactName: String?): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.CALL_INCOMING,
            payload = buildJsonObject {
                put("number", number)
                if (contactName != null) put("contactName", contactName)
            },
        )

    fun callAction(action: String, number: String? = null): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.CALL_ACTION,
            payload = buildJsonObject {
                put("action", action)
                if (number != null) put("number", number)
            },
        )

    /** Call lifecycle transition: state is "ringing" | "active" | "ended". */
    fun callState(state: String, number: String, contactName: String?): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.CALL_STATE,
            payload = buildJsonObject {
                put("state", state)
                put("number", number)
                if (contactName != null) put("contactName", contactName)
            },
        )

    fun clipboard(text: String): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.CLIP_UPDATE,
            payload = buildJsonObject { put("text", text) },
        )

    fun callHistory(records: List<Triple<String, String, Long>>): Message =
        Message(
            id = UUID.randomUUID().toString(),
            type = MessageTypes.CALL_HISTORY,
            payload = buildJsonObject {
                // records as parallel arrays keeps the schema simple and validated
                put("numbers", buildJsonArray { records.forEach { add(it.first) } } )
                put("types", buildJsonArray { records.forEach { add(it.second) } } )
                put("timestamps", buildJsonArray { records.forEach { add(it.third) } } )
            },
        )

    fun meetingStart(meetingId: String, title: String?, startedAt: Long): Message =
        Message(UUID.randomUUID().toString(), MessageTypes.MEETING_START, payload = buildJsonObject {
            put("meetingId", meetingId); if (title != null) put("title", title); put("startedAt", startedAt)
        })

    fun meetingStop(meetingId: String, stoppedAt: Long): Message =
        Message(UUID.randomUUID().toString(), MessageTypes.MEETING_STOP, payload = buildJsonObject {
            put("meetingId", meetingId); put("stoppedAt", stoppedAt)
        })

    fun meetingAudioChunk(meetingId: String, sequence: Int, startedAtMs: Long, endedAtMs: Long, checksum: String, name: String, data: String): Message =
        Message(UUID.randomUUID().toString(), MessageTypes.MEETING_AUDIO_CHUNK_OFFER, payload = buildJsonObject {
            put("meetingId", meetingId); put("sequence", sequence); put("startedAtMs", startedAtMs); put("endedAtMs", endedAtMs)
            put("checksum", checksum); put("name", name); put("data", data)
        })

    fun meetingPhoto(meetingId: String, photoId: String, capturedAtMs: Long, checksum: String, name: String, data: String): Message =
        Message(UUID.randomUUID().toString(), MessageTypes.MEETING_PHOTO_OFFER, payload = buildJsonObject {
            put("meetingId", meetingId); put("photoId", photoId); put("capturedAtMs", capturedAtMs); put("checksum", checksum); put("name", name); put("data", data)
        })
}
