package com.androidbridge.protocol

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.throwable.shouldHaveMessage
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.property.Arb
import io.kotest.property.arbitrary.Codepoint
import io.kotest.property.arbitrary.az
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.boolean
import io.kotest.property.arbitrary.byte
import io.kotest.property.arbitrary.byteArray
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.list
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.map
import io.kotest.property.arbitrary.orNull
import io.kotest.property.arbitrary.string
import io.kotest.property.checkAll
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// ---- Domain generators (PBT-07) ----

private val jsonValueArb: Arb<JsonElement> = Arb.choice(
    Arb.string(0..12, Codepoint.az()).map { JsonPrimitive(it) },
    Arb.int(-100_000, 100_000).map { JsonPrimitive(it) },
    Arb.boolean().map { JsonPrimitive(it) },
)

private val payloadArb: Arb<JsonObject> =
    Arb.map(Arb.string(1..8, Codepoint.az()), jsonValueArb, minSize = 0, maxSize = 6)
        .map { JsonObject(it) }

private val messageArb: Arb<Message> = Arb.bind(
    Arb.string(1..20, Codepoint.az()),
    Arb.element(MessageTypes.known.toList()),
    Arb.string(1..20, Codepoint.az()).orNull(0.5),
    payloadArb,
) { id, type, replyTo, payload -> Message(id = id, type = type, replyTo = replyTo, payload = payload) }

class ProtocolPropertyTest : StringSpec({

    "PBT-02: decode(encode(m)) == m for all valid control messages" {
        checkAll(messageArb) { m ->
            MessageCodec.decode(MessageCodec.encode(m)) shouldBe m
        }
    }

    "PBT-03: length-prefixed control framing is self-delimiting" {
        checkAll(Arb.list(messageArb, 0..5)) { msgs ->
            val bytes = msgs.fold(ByteArray(0)) { acc, m -> acc + MessageCodec.encode(m) }
            MessageCodec.decodeStream(bytes) shouldBe msgs
        }
    }

    "PBT-03: decodeFrame(encodeFrame(h, p)) == (h, p) for all frames" {
        checkAll(
            Arb.long(0, 0xFFFFFFFFL),
            Arb.long(0, 0xFFFFFFFFL),
            Arb.int(0, 255),
            Arb.byteArray(Arb.int(0, 2048), Arb.byte()),
        ) { streamId, sequence, flags, payload ->
            val header = FrameHeader(streamId, sequence, payload.size, flags)
            FrameCodec.decodeFrame(FrameCodec.encodeFrame(header, payload)) shouldBe Frame(header, payload)
        }
    }
})

class ProtocolExampleTest : StringSpec({

    "encodes a known message with a 4-byte big-endian length prefix" {
        val m = Message(id = "abc", type = MessageTypes.LINK_HEARTBEAT)
        val bytes = MessageCodec.encode(m)
        val declaredLen = readU32BE(bytes, 0)
        declaredLen shouldBe (bytes.size - 4).toLong()
        MessageCodec.decode(bytes) shouldBe m
    }

    "rejects an unknown message type (fail-closed)" {
        val raw = MessageCodec.encode(Message(id = "x", type = MessageTypes.LINK_HELLO))
        // Re-create with an unknown type by hand-encoding to bypass the registry on encode path:
        val json = """{"id":"x","type":"bogus.type"}"""
        val body = json.encodeToByteArray()
        val framed = ByteArray(4 + body.size)
        writeU32BE(framed, 0, body.size.toLong())
        body.copyInto(framed, 4)
        shouldThrow<ProtocolException> { MessageCodec.decode(framed) }
            .shouldHaveMessage(ProtocolErrorCode.UNKNOWN_TYPE.name)
        raw.isNotEmpty() shouldBe true
    }

    "rejects a control message whose declared length exceeds 1 MiB (anti-DoS)" {
        val oversize = ByteArray(8)
        writeU32BE(oversize, 0, MAX_CONTROL_BYTES + 1)
        shouldThrow<ProtocolException> { MessageCodec.decode(oversize) }
            .shouldHaveMessage(ProtocolErrorCode.OVERSIZE.name)
    }

    "rejects a version mismatch" {
        val json = """{"id":"x","type":"link.hello","protocolVersion":2}"""
        val body = json.encodeToByteArray()
        val framed = ByteArray(4 + body.size)
        writeU32BE(framed, 0, body.size.toLong())
        body.copyInto(framed, 4)
        shouldThrow<ProtocolException> { MessageCodec.decode(framed) }
            .shouldHaveMessage(ProtocolErrorCode.VERSION_MISMATCH.name)
    }

    "marks END_OF_STREAM frames" {
        val h = FrameHeader(streamId = 7, sequence = 3, length = 0, flags = FLAG_END_OF_STREAM)
        val decoded = FrameCodec.decodeFrame(FrameCodec.encodeFrame(h, ByteArray(0)))
        decoded.header.isEndOfStream shouldBe true
    }
})
