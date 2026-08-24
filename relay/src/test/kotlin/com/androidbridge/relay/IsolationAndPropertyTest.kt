package com.androidbridge.relay

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.byte
import io.kotest.property.arbitrary.byteArray
import io.kotest.property.arbitrary.int
import io.kotest.property.checkAll
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.time.Duration.Companion.milliseconds

class IsolationAndPropertyTest : FunSpec({
    test("router denies cross-pair forwarding") {
        val pairs = mapOf("mac-a" to "phone-a", "phone-a" to "mac-a", "mac-b" to "phone-b", "phone-b" to "mac-b")
        val registry = ConnectionRegistry({ pairs[it] }, 50.milliseconds)
        val phoneB = RecordingConnection()
        registry.register("phone-b", phoneB)

        registry.forward("mac-a", byteArrayOf(1, 2, 3)) shouldBe ForwardResult.PEER_ABSENT
        phoneB.payloads shouldContainExactly emptyList()
    }

    test("new connection atomically replaces old connection") {
        checkAll(iterations = 100, Arb.int(1..20)) { replacements ->
            val registry = ConnectionRegistry({ null }, 50.milliseconds)
            val connections = List(replacements) { RecordingConnection() }
            connections.forEach { registry.register("device", it) }

            connections.dropLast(1).all { it.closed.isCompleted } shouldBe true
            connections.last().closed.isCompleted shouldBe false
        }
    }

    test("random connect and disconnect schedules retain only current generation") {
        checkAll(iterations = 100, Arb.int(1..50)) { operations ->
            val registry = ConnectionRegistry({ null }, 50.milliseconds)
            var current: RecordingConnection? = null
            repeat(operations) { index ->
                val next = RecordingConnection()
                registry.register("device", next)
                if (index % 3 == 0 && current != null) registry.unregister("device", current!!)
                current = next
            }
            registry.isCurrent("device", current!!) shouldBe true
        }
    }

    test("forwarding preserves arbitrary bytes exactly") {
        checkAll(iterations = 200, Arb.byteArray(Arb.int(0..4_096), Arb.byte())) { payload ->
            val registry = ConnectionRegistry({ if (it == "sender") "peer" else "sender" }, 50.milliseconds)
            val peer = RecordingConnection()
            registry.register("peer", peer)

            registry.forward("sender", payload) shouldBe ForwardResult.FORWARDED
            peer.payloads.single().shouldBe(payload)
        }
    }

    test("token verification is constant-shape and rejects mutations") {
        checkAll(iterations = 200, Arb.byteArray(Arb.int(16..64), Arb.byte())) { bytes ->
            val token = bytes.joinToString("") { "%02x".format(it) }
            val hash = TokenHasher.hash(token)
            TokenHasher.matches(token, hash) shouldBe true
            TokenHasher.matches("x$token", hash) shouldBe false
        }
    }
})

internal class RecordingConnection : RelayConnection {
    val payloads = mutableListOf<ByteArray>()
    val closed = CompletableDeferred<Unit>()

    override suspend fun send(payload: ByteArray) {
        payloads += payload.copyOf()
    }

    override suspend fun close(reason: String) {
        closed.complete(Unit)
    }
}
