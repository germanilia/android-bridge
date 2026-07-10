package com.androidbridge.protocol

import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.collections.shouldContainExactlyInAnyOrder
import java.io.File

/**
 * Cross-language interop: decodes the same canonical wire vectors that the Swift `ProtocolCheck`
 * suite decodes (protocol/vectors/control-messages.jsonl). Proves both implementations accept the
 * identical on-the-wire JSON contract.
 */
class InteropVectorTest : StringSpec({

    "decodes shared cross-language wire vectors" {
        // Gradle runs tests with working dir = module dir (protocol/kotlin); vectors are a sibling.
        val candidates = listOf(
            File("../vectors/control-messages.jsonl"),
            File("protocol/vectors/control-messages.jsonl"),
        )
        val file = candidates.firstOrNull { it.exists() }
            ?: error("vectors file not found in: ${candidates.map { it.absolutePath }}")

        val lines = file.readLines().filter { it.isNotBlank() }
        lines.isNotEmpty() shouldBe true

        val decodedTypes = lines.map { line ->
            val body = line.encodeToByteArray()
            val framed = ByteArray(4 + body.size)
            writeU32BE(framed, 0, body.size.toLong())
            body.copyInto(framed, 4)
            MessageCodec.decode(framed).type
        }

        // Every decoded type is a registered type.
        decodedTypes.all { it in MessageTypes.known } shouldBe true
        decodedTypes shouldContainExactlyInAnyOrder listOf(
            MessageTypes.LINK_HELLO, MessageTypes.LINK_HEARTBEAT, MessageTypes.CLIP_UPDATE,
            MessageTypes.CALL_ACTION, MessageTypes.NOTIF_POSTED, MessageTypes.FILE_OFFER,
        )
    }
})
