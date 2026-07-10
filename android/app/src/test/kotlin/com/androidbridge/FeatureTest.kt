package com.androidbridge

import com.androidbridge.feature.ClipboardSyncMode
import com.androidbridge.feature.ClipboardSyncPolicy
import com.androidbridge.feature.Mappers
import com.androidbridge.protocol.MessageTypes
import com.androidbridge.protocol.validate
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import kotlinx.serialization.json.jsonPrimitive

class ClipboardSyncTest : StringSpec({
    "manual is the default and only sends on explicit push" {
        val p = ClipboardSyncPolicy()
        p.mode shouldBe ClipboardSyncMode.MANUAL
        p.shouldSend(userInitiated = false) shouldBe false
        p.shouldSend(userInitiated = true) shouldBe true
    }
    "auto sends on any local copy" {
        val p = ClipboardSyncPolicy(ClipboardSyncMode.AUTO)
        p.shouldSend(userInitiated = false) shouldBe true
    }
})

class MappersTest : StringSpec({
    "notification maps to a valid notif.posted message" {
        val m = Mappers.notification("com.whatsapp", "Mom", "hi", 123L)
        m.type shouldBe MessageTypes.NOTIF_POSTED
        validate(m).valid shouldBe true
    }
    "sms maps to a valid sms.received message" {
        val m = Mappers.smsReceived(1L, "+15551234567", "hello", 456L)
        m.type shouldBe MessageTypes.SMS_RECEIVED
        validate(m).valid shouldBe true
    }
    "incoming call maps to a valid call.incoming message" {
        val m = Mappers.incomingCall("+15551234567", "Alice")
        m.type shouldBe MessageTypes.CALL_INCOMING
        validate(m).valid shouldBe true
    }
    "call action maps to a valid call.action message" {
        val m = Mappers.callAction("answer")
        m.type shouldBe MessageTypes.CALL_ACTION
        validate(m).valid shouldBe true
    }
    "call dial action carries the number for the phone to place the call" {
        val m = Mappers.callAction("dial", "+15550100")
        m.type shouldBe MessageTypes.CALL_ACTION
        m.payload["action"]!!.jsonPrimitive.content shouldBe "dial"
        m.payload["number"]!!.jsonPrimitive.content shouldBe "+15550100"
        validate(m).valid shouldBe true
    }
    "clipboard maps to a valid clip.update message" {
        val m = Mappers.clipboard("copied text")
        m.type shouldBe MessageTypes.CLIP_UPDATE
        validate(m).valid shouldBe true
    }
    "meeting audio chunk maps to a valid meeting message" {
        val m = Mappers.meetingAudioChunk("m1", 1, 0, 60_000, "abc", "chunk.3gp", "ZGF0YQ==")
        m.type shouldBe MessageTypes.MEETING_AUDIO_CHUNK_OFFER
        m.payload["meetingId"]!!.jsonPrimitive.content shouldBe "m1"
        validate(m).valid shouldBe true
    }
})
