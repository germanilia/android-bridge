package com.androidbridge

import com.androidbridge.core.ConnectionState
import com.androidbridge.core.ConnectionStateMachine
import com.androidbridge.core.FeatureId
import com.androidbridge.core.InMemorySecureStore
import com.androidbridge.core.LinkLogger
import com.androidbridge.core.MessageRouter
import com.androidbridge.core.PairingManager
import com.androidbridge.core.PluginRegistry
import com.androidbridge.core.StreamChunker
import com.androidbridge.core.StreamReassembler
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageTypes
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.byte
import io.kotest.property.arbitrary.byteArray
import io.kotest.property.arbitrary.int
import io.kotest.property.checkAll

class MessageRouterTest : StringSpec({
    "routes a valid message to its registered handler" {
        val router = MessageRouter()
        var received: Message? = null
        router.register(MessageTypes.CLIP_UPDATE) { received = it }
        val msg = Message(id = "1", type = MessageTypes.CLIP_UPDATE)
        router.route(msg) shouldBe true
        received shouldBe msg
    }

    "drops an unrouted (no handler) message — fail-closed" {
        val router = MessageRouter()
        router.route(Message(id = "1", type = MessageTypes.SMS_RECEIVED)) shouldBe false
    }

    "drops an invalid (version mismatch) message" {
        val router = MessageRouter()
        router.register(MessageTypes.CLIP_UPDATE) { }
        router.route(Message(id = "1", type = MessageTypes.CLIP_UPDATE, protocolVersion = 2)) shouldBe false
    }
})

class PluginRegistryTest : StringSpec({
    "all features enabled by default" {
        val reg = PluginRegistry()
        FeatureId.values().forEach { reg.isEnabled(it) shouldBe true }
    }
    "disable then enable a feature" {
        val reg = PluginRegistry()
        reg.disable(FeatureId.SMS)
        reg.isEnabled(FeatureId.SMS) shouldBe false
        reg.enable(FeatureId.SMS)
        reg.isEnabled(FeatureId.SMS) shouldBe true
    }
})

class PairingTest : StringSpec({
    "QR create → consume round-trips and pins the peer" {
        val deviceA = PairingManager(InMemorySecureStore())
        val deviceB = PairingManager(InMemorySecureStore())
        val idA = deviceA.generateIdentity("galaxy")
        val qr = deviceA.createPairingQr(idA, host = "192.168.1.5", port = 5599)

        val pinned = deviceB.consumePairingQr(qr)
        pinned.deviceId shouldBe idA.deviceId
        pinned.deviceName shouldBe "galaxy"
        deviceB.isPinned(pinned.fingerprint) shouldBe true
        deviceB.listPaired().size shouldBe 1
    }

    "fingerprint is deterministic for the same key" {
        val pm = PairingManager(InMemorySecureStore())
        val id = pm.generateIdentity("mac")
        pm.fingerprintOf(id.publicKeyB64) shouldBe pm.fingerprintOf(id.publicKeyB64)
    }

    "unpair removes the peer" {
        val a = PairingManager(InMemorySecureStore())
        val b = PairingManager(InMemorySecureStore())
        val idA = a.generateIdentity("galaxy")
        val peer = b.consumePairingQr(a.createPairingQr(idA, "h", 1))
        b.unpair(peer.deviceId)
        b.listPaired().size shouldBe 0
    }

    "tampered fingerprint is rejected" {
        val a = PairingManager(InMemorySecureStore())
        val b = PairingManager(InMemorySecureStore())
        val idA = a.generateIdentity("galaxy")
        val qr = a.createPairingQr(idA, "h", 1).replace(
            a.fingerprintOf(idA.publicKeyB64), "00:11:22",
        )
        runCatching { b.consumePairingQr(qr) }.isFailure shouldBe true
    }
})

class StreamTest : StringSpec({
    "PBT-03: chunk then reassemble round-trips arbitrary payloads" {
        checkAll(Arb.byteArray(Arb.int(0, 5000), Arb.byte())) { data ->
            val frames = StreamChunker.chunk(streamId = 42, data = data, chunkSize = 256)
            val reasm = StreamReassembler(42)
            frames.forEach { reasm.accept(it) shouldBe true }
            reasm.complete shouldBe true
            reasm.result().toList() shouldBe data.toList()
        }
    }

    "last frame carries END_OF_STREAM" {
        val frames = StreamChunker.chunk(1, ByteArray(600), chunkSize = 256)
        frames.last().header.isEndOfStream shouldBe true
        frames.dropLast(1).all { !it.header.isEndOfStream } shouldBe true
    }

    "reassembler faults on a sequence gap" {
        val frames = StreamChunker.chunk(1, ByteArray(600), chunkSize = 256)
        val reasm = StreamReassembler(1)
        reasm.accept(frames[0]) shouldBe true
        reasm.accept(frames[2]) shouldBe false // skipped seq 1
    }
})

class ConnectionStateMachineTest : StringSpec({
    "drives discovery → connecting → connected" {
        val sm = ConnectionStateMachine()
        sm.onEvent(ConnectionStateMachine.Event.START_DISCOVERY) shouldBe ConnectionState.DISCOVERING
        sm.onEvent(ConnectionStateMachine.Event.PEER_FOUND) shouldBe ConnectionState.CONNECTING
        sm.onEvent(ConnectionStateMachine.Event.CONNECTED) shouldBe ConnectionState.CONNECTED
    }
    "a drop while connected triggers reconnecting" {
        val sm = ConnectionStateMachine(ConnectionState.CONNECTED)
        sm.onEvent(ConnectionStateMachine.Event.LINK_DROPPED) shouldBe ConnectionState.RECONNECTING
    }
})

class LinkLoggerTest : StringSpec({
    "redacts forbidden fields (CC-PRIV)" {
        val safe = LinkLogger.redact(mapOf("pkg" to "com.x", "body" to "secret", "number" to "555"))
        safe.containsKey("body") shouldBe false
        safe.containsKey("number") shouldBe false
        safe["pkg"] shouldNotBe null
    }
})
