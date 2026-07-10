package com.androidbridge

import com.androidbridge.core.CertFactory
import com.androidbridge.core.TlsLink
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageTypes
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.shouldBe
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Real mutual-TLS integration test (U3), fully in-process over localhost — no device needed.
 * Proves: two mutually-pinned peers complete a mTLS handshake and exchange protocol messages, and an
 * unpinned peer is rejected at the TLS layer (CC-SEC / SECURITY-06/-08).
 */
class TlsIntegrationTest : StringSpec({

    "mutually-pinned peers complete mTLS and exchange messages" {
        val serverId = CertFactory.generateSelfSigned("device-a")
        val clientId = CertFactory.generateSelfSigned("device-b")

        val server = TlsLink.openServer(serverId, pinnedPeerFingerprint = clientId.fingerprint)
        val port = server.localPort
        val serverReceived = ArrayBlockingQueue<Message>(1)

        val serverThread = thread {
            server.use {
                val session = TlsLink.accept(it)
                val msg = session.receive()
                serverReceived.add(msg)
                session.send(Message(id = "reply", type = MessageTypes.LINK_HEARTBEAT, replyTo = msg.id))
                session.close()
            }
        }

        val client = TlsLink.connect("127.0.0.1", port, clientId, pinnedPeerFingerprint = serverId.fingerprint)
        client.send(Message(id = "hello-1", type = MessageTypes.LINK_HELLO))
        val reply = client.receive()

        reply.type shouldBe MessageTypes.LINK_HEARTBEAT
        reply.replyTo shouldBe "hello-1"

        val got = serverReceived.poll(5, TimeUnit.SECONDS)
        got?.type shouldBe MessageTypes.LINK_HELLO

        client.close()
        serverThread.join(2000)
    }

    "an unpinned peer is rejected at the TLS handshake (CC-SEC)" {
        val serverId = CertFactory.generateSelfSigned("device-a")
        val clientId = CertFactory.generateSelfSigned("device-b")
        val attackerId = CertFactory.generateSelfSigned("attacker")

        // Server only pins device-b; the attacker is not pinned.
        val server = TlsLink.openServer(serverId, pinnedPeerFingerprint = clientId.fingerprint)
        val port = server.localPort

        val serverThread = thread {
            server.use { runCatching { TlsLink.accept(it).receive() } }
        }

        shouldThrow<Exception> {
            val evil = TlsLink.connect("127.0.0.1", port, attackerId, pinnedPeerFingerprint = serverId.fingerprint)
            evil.send(Message(id = "x", type = MessageTypes.LINK_HELLO))
            evil.receive()
        }

        serverThread.join(2000)
    }
})
