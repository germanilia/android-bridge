package com.androidbridge

import com.androidbridge.core.InMemorySecureStore
import com.androidbridge.relay.AppPrivateRelayStore
import com.androidbridge.relay.DirectFirstSessionGate
import com.androidbridge.relay.EnrollmentResult
import com.androidbridge.relay.JournalEntry
import com.androidbridge.relay.PendingDurablePayload
import com.androidbridge.relay.ReceiveDecision
import com.androidbridge.relay.RelayCredentials
import com.androidbridge.relay.RelayEndpoint
import com.androidbridge.relay.RelayEnrollmentClient
import com.androidbridge.relay.RelayEvent
import com.androidbridge.relay.RelayJournal
import com.androidbridge.relay.RelayRoute
import com.androidbridge.relay.RelaySettingsRepository
import com.androidbridge.relay.RelaySpool
import com.androidbridge.relay.RelayWebSocketTransport
import com.androidbridge.relay.RelayWebSocketTransport.Companion.MAX_RELAY_FRAME_BYTES
import com.androidbridge.relay.ReplayClass
import com.androidbridge.relay.ReplayClassifier
import com.androidbridge.relay.ResumeReceiver
import com.androidbridge.protocol.MAX_CONTROL_BYTES
import com.androidbridge.protocol.MessageTypes
import com.androidbridge.protocol.ProtocolErrorCode
import com.androidbridge.protocol.ProtocolException
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import io.kotest.matchers.shouldNotBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.byte
import io.kotest.property.arbitrary.byteArray
import io.kotest.property.arbitrary.int
import io.kotest.property.checkAll
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.HttpUrl
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.ByteString
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger

class RelaySettingsTest : StringSpec({
    "relay endpoint requires secure WebSocket and no embedded secrets" {
        RelayEndpoint.parse("wss://relay.homeserver").getOrThrow().webSocketUrl.scheme shouldBe "wss"
        RelayEndpoint.parse("ws://relay.homeserver").isFailure shouldBe true
        RelayEndpoint.parse("wss://user:pass@relay.homeserver").isFailure shouldBe true
        RelayEndpoint.parse("wss://relay.homeserver/bridge").isFailure shouldBe true
        RelayEndpoint.parse("wss://relay.homeserver?token=secret").isFailure shouldBe true
    }

    "settings stay disabled by default and credentials can be removed" {
        val secureStore = InMemorySecureStore()
        val repository = RelaySettingsRepository(secureStore)
        repository.load().enabled shouldBe false

        repository.saveEndpoint("wss://relay.homeserver")
        repository.saveEnrollment(EnrollmentResult("android-1", "credential-1"))
        repository.setEnabled(true)

        repository.load().let {
            it.enabled shouldBe true
            it.endpoint shouldBe "wss://relay.homeserver"
            it.credentials shouldNotBe null
        }

        repository.clearCredentials()
        repository.load().let {
            it.enabled shouldBe false
            it.credentials shouldBe null
        }
    }
})

class RelayEnrollmentTest : StringSpec({
    "enrollment posts invitation without putting it in URL" {
        val server = MockWebServer()
        server.enqueue(MockResponse().setResponseCode(201).setBody("""{"deviceId":"android-1","credential":"credential-1"}"""))
        server.start()
        try {
            val client = RelayEnrollmentClient()
            val result = client.enrollAt(server.url("/v1/enrollment/invitation"), "invite-1234567890", "android-1")
            result shouldBe EnrollmentResult("android-1", "credential-1")
            val request = server.takeRequest()
            request.method shouldBe "POST"
            request.path shouldBe "/v1/enrollment/invitation"
            request.body.readUtf8().contains("invite-1234567890") shouldBe true
            request.requestUrl.toString().contains("invite-1234567890") shouldBe false
        } finally {
            server.shutdown()
        }
    }
})

class DirectFirstSessionTest : StringSpec({
    "stale relay callback cannot replace a newer generation" {
        val gate = DirectFirstSessionGate()
        val stale = gate.beginAttempt()
        val current = gate.beginAttempt()

        gate.adopt(stale, RelayRoute.RELAY) shouldBe false
        gate.adopt(current, RelayRoute.RELAY) shouldBe true
        gate.route shouldBe RelayRoute.RELAY
    }

    "direct route replaces relay in the same generation and relay cannot replace direct" {
        val gate = DirectFirstSessionGate()
        val generation = gate.beginAttempt()
        gate.adopt(generation, RelayRoute.RELAY) shouldBe true
        gate.adopt(generation, RelayRoute.DIRECT) shouldBe true
        gate.adopt(generation, RelayRoute.RELAY) shouldBe false
        gate.route shouldBe RelayRoute.DIRECT
    }
})

class ReplayClassificationTest : StringSpec({
    "time-sensitive input and call controls are live-only" {
        listOf(
            MessageTypes.LINK_HEARTBEAT,
            MessageTypes.SCREEN_FRAME,
            MessageTypes.SCREEN_REQUEST,
            MessageTypes.INPUT_TAP,
            MessageTypes.INPUT_SWIPE,
            MessageTypes.CALL_INCOMING,
            MessageTypes.CALL_ACTION,
        ).forEach { ReplayClassifier.classify(it) shouldBe ReplayClass.LIVE_ONLY }
    }

    "clipboard coalesces and owned-byte transfers use spool" {
        ReplayClassifier.classify(MessageTypes.CLIP_UPDATE) shouldBe ReplayClass.COALESCING
        ReplayClassifier.classify(MessageTypes.FILE_CHUNK) shouldBe ReplayClass.SPOOLED
        ReplayClassifier.classify(MessageTypes.MEETING_PHOTO_OFFER) shouldBe ReplayClass.SPOOLED
        ReplayClassifier.classify(MessageTypes.MEETING_AUDIO_CHUNK_OFFER) shouldBe ReplayClass.SPOOLED
    }

    "durable asynchronous events replay" {
        ReplayClassifier.classify(MessageTypes.NOTIF_POSTED) shouldBe ReplayClass.REPLAY_SAFE
        ReplayClassifier.classify(MessageTypes.SMS_RECEIVED) shouldBe ReplayClass.REPLAY_SAFE
        ReplayClassifier.classify(MessageTypes.CALL_STATE) shouldBe ReplayClass.REPLAY_SAFE
    }
})

class RelayJournalTest : StringSpec({
    "journal survives restart and resume returns unacknowledged suffix" {
        val root = Files.createTempDirectory("relay-journal").toFile()
        try {
            val journal = RelayJournal(root, "android")
            val first = journal.append("op-1", MessageTypes.NOTIF_POSTED, ReplayClass.REPLAY_SAFE, byteArrayOf(1))
            val second = journal.append("op-2", MessageTypes.SMS_RECEIVED, ReplayClass.REPLAY_SAFE, byteArrayOf(2))
            journal.acknowledge(first.sequence)

            val reopened = RelayJournal(root, "android")
            reopened.acknowledgedSequence shouldBe first.sequence
            reopened.pending().map(JournalEntry::operationId) shouldContainExactly listOf(second.operationId)
        } finally {
            root.deleteRecursively()
        }
    }

    "acknowledgements cannot move backward or beyond high-water mark" {
        val root = Files.createTempDirectory("relay-ack").toFile()
        try {
            val journal = RelayJournal(root, "android")
            journal.append("op-1", MessageTypes.NOTIF_POSTED, ReplayClass.REPLAY_SAFE, byteArrayOf())
            journal.acknowledge(1)
            runCatching { journal.acknowledge(0) }.isFailure shouldBe true
            runCatching { journal.acknowledge(2) }.isFailure shouldBe true
        } finally {
            root.deleteRecursively()
        }
    }

    "pending clipboard values coalesce to latest unacknowledged value" {
        val root = Files.createTempDirectory("relay-coalesce").toFile()
        try {
            val journal = RelayJournal(root, "android")
            journal.append("clip-1", MessageTypes.CLIP_UPDATE, ReplayClass.COALESCING, byteArrayOf(1))
            journal.append("sms-1", MessageTypes.SMS_RECEIVED, ReplayClass.REPLAY_SAFE, byteArrayOf(2))
            journal.append("clip-2", MessageTypes.CLIP_UPDATE, ReplayClass.COALESCING, byteArrayOf(3))
            journal.pending().map(JournalEntry::operationId) shouldContainExactly listOf("sms-1", "clip-2")
        } finally {
            root.deleteRecursively()
        }
    }
})

class RelaySpoolTest : StringSpec({
    "spool round-trips arbitrary bytes by digest" {
        val root = Files.createTempDirectory("relay-spool-pbt").toFile()
        try {
            val spool = RelaySpool(root)
            checkAll(iterations = 100, Arb.byteArray(Arb.int(0, 16_384), Arb.byte())) { bytes ->
                val ref = spool.put(bytes)
                spool.read(ref.sha256).toList() shouldBe bytes.toList()
            }
        } finally {
            root.deleteRecursively()
        }
    }

    "spool is content-addressed and survives reconstruction" {
        val root = Files.createTempDirectory("relay-spool").toFile()
        try {
            val spool = RelaySpool(root)
            val first = spool.put("payload".encodeToByteArray())
            val second = spool.put("payload".encodeToByteArray())
            first shouldBe second
            RelaySpool(root).read(first.sha256).decodeToString() shouldBe "payload"
        } finally {
            root.deleteRecursively()
        }
    }

    "acknowledging a spooled operation removes owned bytes" {
        val filesDir = Files.createTempDirectory("app-spool-ack").toFile()
        try {
            val store = AppPrivateRelayStore(filesDir, "android")
            val entry = store.enqueue(PendingDurablePayload(
                operationId = "file-1",
                messageType = MessageTypes.FILE_CHUNK,
                metadata = byteArrayOf(1),
                ownedBytes = byteArrayOf(4, 5).inputStream(),
            ))
            store.spool.contains(entry.spool!!.sha256) shouldBe true
            store.acknowledge(entry.sequence)
            store.spool.contains(entry.spool.sha256) shouldBe false
        } finally {
            filesDir.deleteRecursively()
        }
    }

    "app-private store keeps journal and blobs under supplied files directory" {
        val filesDir = Files.createTempDirectory("app-files").toFile()
        try {
            val store = AppPrivateRelayStore(filesDir, "android")
            store.journal.append("op-1", MessageTypes.FILE_CHUNK, ReplayClass.SPOOLED, byteArrayOf(), store.spool.put(byteArrayOf(4, 5)))
            store.root.canonicalPath.startsWith(filesDir.canonicalPath) shouldBe true
        } finally {
            filesDir.deleteRecursively()
        }
    }
})

class ResumeReceiverTest : StringSpec({
    "duplicate operation is acknowledged without reapply after restart" {
        val root = Files.createTempDirectory("relay-receiver").toFile()
        try {
            val receiver = ResumeReceiver(root)
            receiver.classify(1, "op-1") shouldBe ReceiveDecision.APPLY
            receiver.commit(1, "op-1")

            val reopened = ResumeReceiver(root)
            reopened.classify(1, "op-1") shouldBe ReceiveDecision.DUPLICATE
            reopened.classify(2, "op-1") shouldBe ReceiveDecision.DUPLICATE
            reopened.commit(2, "op-1")
            reopened.classify(4, "op-4") shouldBe ReceiveDecision.OUT_OF_ORDER
            reopened.cursor shouldBe 2
        } finally {
            root.deleteRecursively()
        }
    }
})

class RelayWebSocketTransportTest : StringSpec({
    "OkHttp transport authenticates and carries bounded binary frames" {
        val server = MockWebServer()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                webSocket.send(bytes)
            }
        }))
        server.start()
        try {
            val transport = RelayWebSocketTransport()
            val url: HttpUrl = server.url("/v1/connect")
            transport.connectAt(url, RelayCredentials("android-1", "credential-1"), generation = 7)

            runBlocking {
                withTimeout(3_000) {
                    while (transport.events.receive() !is RelayEvent.Open) Unit
                }
                transport.send(byteArrayOf(1, 2, 3)) shouldBe true
                val inbound = withTimeout(3_000) { transport.inbound.receive() }
                inbound.generation shouldBe 7
                inbound.bytes.toList() shouldBe listOf<Byte>(1, 2, 3)
            }
            val request = server.takeRequest()
            request.getHeader("Authorization") shouldBe "Bearer credential-1"
            request.getHeader("X-Device-Id") shouldBe "android-1"
        } finally {
            server.shutdown()
        }
    }

    "transport keeps waiting when relay reports peer absent" {
        val server = MockWebServer()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: okhttp3.Response) {
                webSocket.send("{\"error\":\"peer_absent\"}")
            }
        }))
        server.start()
        try {
            val transport = RelayWebSocketTransport()
            transport.connectAt(server.url("/v1/connect"), RelayCredentials("android-1", "credential-1"), generation = 8)
            runBlocking {
                withTimeout(3_000) {
                    while (transport.events.receive() !is RelayEvent.Waiting) Unit
                }
            }
        } finally {
            server.shutdown()
        }
    }

    "transport keeps the socket open when relay reports a transient error" {
        val observedCloseCode = AtomicInteger(0)
        val server = MockWebServer()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: okhttp3.Response) {
                webSocket.send("{\"error\":\"peer_backpressure\"}")
                webSocket.send(ByteString.of(4, 5, 6))
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                observedCloseCode.set(code)
            }
        }))
        server.start()
        try {
            val transport = RelayWebSocketTransport()
            transport.connectAt(server.url("/v1/connect"), RelayCredentials("android-1", "credential-1"), generation = 9)
            runBlocking {
                withTimeout(3_000) {
                    while (transport.events.receive() !is RelayEvent.Open) Unit
                }
                val inbound = withTimeout(3_000) { transport.inbound.receive() }
                inbound.bytes.toList() shouldBe listOf<Byte>(4, 5, 6)
                withTimeoutOrNull(500) { transport.events.receive() } shouldBe null
            }
            observedCloseCode.get() shouldBe 0
        } finally {
            server.shutdown()
        }
    }

    "transport applies backpressure instead of closing when the receiver is behind" {
        val observedCloseCode = AtomicInteger(0)
        val server = MockWebServer()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: okhttp3.Response) {
                repeat(6) { webSocket.send(ByteString.of(it.toByte())) }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                observedCloseCode.set(code)
            }
        }))
        server.start()
        try {
            val transport = RelayWebSocketTransport(inboundCapacity = 1)
            transport.connectAt(server.url("/v1/connect"), RelayCredentials("android-1", "credential-1"), generation = 11)
            runBlocking {
                withTimeout(3_000) {
                    while (transport.events.receive() !is RelayEvent.Open) Unit
                }
                val received = (0 until 6).map {
                    withTimeout(5_000) { transport.inbound.receive() }.bytes.single()
                }
                received shouldBe listOf<Byte>(0, 1, 2, 3, 4, 5)
            }
            observedCloseCode.get() shouldBe 0
        } finally {
            server.shutdown()
        }
    }

    "transport rejects oversized outbound frame" {
        val transport = RelayWebSocketTransport()
        runCatching { transport.send(ByteArray(MAX_RELAY_FRAME_BYTES + 1)) }.isFailure shouldBe true
    }
})

class AndroidTlsLengthTest : StringSpec({
    "TLS receive length rejects oversized unsigned value before allocation" {
        val failure = runCatching { com.androidbridge.core.checkedControlLength(0xffff_ffffL) }.exceptionOrNull()
        failure shouldNotBe null
        (failure as ProtocolException).code shouldBe ProtocolErrorCode.OVERSIZE
    }

    "TLS receive length accepts protocol maximum" {
        com.androidbridge.core.checkedControlLength(MAX_CONTROL_BYTES) shouldBe MAX_CONTROL_BYTES.toInt()
    }
})
