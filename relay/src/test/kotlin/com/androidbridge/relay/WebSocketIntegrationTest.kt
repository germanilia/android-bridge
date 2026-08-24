package com.androidbridge.relay

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.client.request.header
import io.ktor.http.HttpHeaders
import io.ktor.server.testing.testApplication
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readBytes
import io.ktor.websocket.readText
import io.ktor.websocket.send
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

class WebSocketIntegrationTest : FunSpec({
    test("WSS connection forwards binary frames byte-exact to paired peer") {
        testApplication {
            installTestRelay()
            val pair = enrollPair(jsonClient())
            val wsClient = createClient { install(WebSockets) }
            val phone = wsClient.authenticatedSession("phone-1", pair.phoneCredential)
            val mac = wsClient.authenticatedSession("mac-1", pair.macCredential)
            val payload = byteArrayOf(0, 1, 2, 3, -1, 42)

            mac.send(Frame.Binary(true, payload))
            val received = (phone.incoming.receive() as Frame.Binary).readBytes()
            received.contentEquals(payload) shouldBe true

            mac.close()
            phone.close()
        }
    }

    test("absent peer rejects immediately without queueing payload") {
        testApplication {
            installTestRelay()
            val macCredential = enrollMac(jsonClient()).credential
            val wsClient = createClient { install(WebSockets) }
            val mac = wsClient.authenticatedSession("mac-1", macCredential)

            mac.send(Frame.Binary(true, byteArrayOf(9, 8, 7)))
            (mac.incoming.receive() as Frame.Text).readText() shouldContain "peer_absent"
            mac.close()
        }
    }

    test("sender remains connected while peer disconnects and resumes after peer reconnects") {
        testApplication {
            installTestRelay()
            val pair = enrollPair(jsonClient())
            val wsClient = createClient { install(WebSockets) }
            val mac = wsClient.authenticatedSession("mac-1", pair.macCredential)
            val firstPhone = wsClient.authenticatedSession("phone-1", pair.phoneCredential)
            firstPhone.close()

            withTimeout(2_000) {
                while (true) {
                    mac.send(Frame.Binary(true, byteArrayOf(1)))
                    val response = withTimeoutOrNull(100) { mac.incoming.receive() }
                    if (response is Frame.Text && response.readText().contains("peer_absent")) break
                }
            }

            val resumedPhone = wsClient.authenticatedSession("phone-1", pair.phoneCredential)
            val resumedPayload = byteArrayOf(4, 5, 6)
            mac.send(Frame.Binary(true, resumedPayload))
            val received = (resumedPhone.incoming.receive() as Frame.Binary).readBytes()
            received.contentEquals(resumedPayload) shouldBe true

            mac.close()
            resumedPhone.close()
        }
    }

    test("oversized frame closes connection and is never forwarded") {
        testApplication {
            installTestRelay(maxFrameBytes = 8)
            val pair = enrollPair(jsonClient())
            val wsClient = createClient { install(WebSockets) }
            val phone = wsClient.authenticatedSession("phone-1", pair.phoneCredential)
            val mac = wsClient.authenticatedSession("mac-1", pair.macCredential)

            mac.send(Frame.Binary(true, ByteArray(9)))
            val senderResponse = withTimeoutOrNull(500) { runCatching { mac.incoming.receive() }.getOrNull() }
            (senderResponse is Frame.Binary) shouldBe false
            withTimeoutOrNull(200) { phone.incoming.receive() } shouldBe null

            mac.close()
            phone.close()
        }
    }
})

private suspend fun io.ktor.client.HttpClient.authenticatedSession(deviceId: String, credential: String) =
    webSocketSession("/v1/connect") {
        header("X-Device-Id", deviceId)
        header(HttpHeaders.Authorization, "Bearer $credential")
    }
