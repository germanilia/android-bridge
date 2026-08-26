package com.androidbridge.relay

import com.androidbridge.protocol.MAX_CONTROL_BYTES
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.util.concurrent.TimeUnit

sealed interface RelayEvent {
    val generation: Long
    data class Open(override val generation: Long) : RelayEvent
    data class Waiting(override val generation: Long) : RelayEvent
    data class Closed(override val generation: Long, val code: Int = 0, val reason: String = "") : RelayEvent
    data class Failure(override val generation: Long, val errorType: String) : RelayEvent
}

data class RelayInboundFrame(val generation: Long, val bytes: ByteArray)

/** WSS is a byte transport. Relay envelope/delta models plug in through [RelayMessageAdapter]. */
class RelayWebSocketTransport(
    private val client: OkHttpClient = OkHttpClient.Builder().pingInterval(10, TimeUnit.SECONDS).build(),
    inboundCapacity: Int = INBOUND_CAPACITY,
) {
    private val eventChannel = Channel<RelayEvent>(Channel.BUFFERED)
    private val inboundChannel = Channel<RelayInboundFrame>(inboundCapacity)
    val events: ReceiveChannel<RelayEvent> = eventChannel
    val inbound: ReceiveChannel<RelayInboundFrame> = inboundChannel
    @Volatile private var socket: WebSocket? = null

    fun connect(endpoint: RelayEndpoint, credentials: RelayCredentials, generation: Long) =
        connectAt(endpoint.connectionUrl(), credentials, generation)

    internal fun connectAt(url: HttpUrl, credentials: RelayCredentials, generation: Long) {
        require(credentials.deviceId.isNotBlank() && credentials.credential.isNotBlank())
        socket?.cancel()
        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer ${credentials.credential}")
            .header("X-Device-Id", credentials.deviceId)
            .build()
        socket = client.newWebSocket(request, listener(generation))
    }

    fun send(bytes: ByteArray): Boolean {
        require(bytes.size <= MAX_RELAY_FRAME_BYTES) { "Relay frame too large" }
        return socket?.send(bytes.toByteString()) == true
    }

    fun close() {
        socket?.close(1000, "disabled")
        socket = null
    }

    private fun listener(generation: Long) = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            eventChannel.trySend(RelayEvent.Open(generation))
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            if (bytes.size > MAX_RELAY_FRAME_BYTES) {
                webSocket.close(1009, "frame too large")
                return
            }
            val frame = RelayInboundFrame(generation, bytes.toByteArray())
            if (inboundChannel.trySend(frame).isFailure) {
                // The peer replays its whole journal on reconnect, which briefly outruns the
                // receive loop. Block this reader thread so TCP backpressure reaches the relay
                // rather than killing the link; the wait stays under the ping interval so OkHttp
                // does not time the socket out. If the consumer is still behind, drop this frame:
                // the peer replays unacknowledged operations on the next resume, whereas closing
                // the socket strands the entire batch and guarantees another flap.
                runBlocking {
                    withTimeoutOrNull(INBOUND_BACKPRESSURE_TIMEOUT_MS) { inboundChannel.send(frame) }
                }
            }
        }

        // The relay reports transport-level conditions as a JSON text frame. Parse the code instead
        // of matching one exact string, and never close the socket over it: `peer_backpressure` is
        // transient, and the relay already records every undeliverable frame server-side.
        override fun onMessage(webSocket: WebSocket, text: String) {
            when (RELAY_ERROR_CODE.find(text)?.groupValues?.get(1)) {
                RELAY_ERROR_PEER_ABSENT -> eventChannel.trySend(RelayEvent.Waiting(generation))
                else -> Unit
            }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            eventChannel.trySend(RelayEvent.Closed(generation, code, reason))
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            eventChannel.trySend(RelayEvent.Failure(generation, t::class.java.simpleName))
        }
    }

    companion object {
        const val MAX_RELAY_FRAME_BYTES = MAX_CONTROL_BYTES.toInt() + 4
        private const val RELAY_ERROR_PEER_ABSENT = "peer_absent"
        private const val INBOUND_CAPACITY = 256
        private const val INBOUND_BACKPRESSURE_TIMEOUT_MS = 5_000L
        private val RELAY_ERROR_CODE = Regex("\"error\"\\s*:\\s*\"([a-z_]+)\"")
    }
}

interface RelayMessageAdapter {
    fun encode(message: Message): ByteArray
    fun decode(bytes: ByteArray): Message
}

/** Temporary integration seam until additive relay envelope and Brain delta models land. */
object LengthPrefixedRelayMessageAdapter : RelayMessageAdapter {
    override fun encode(message: Message): ByteArray = MessageCodec.encode(message)
    override fun decode(bytes: ByteArray): Message = MessageCodec.decode(bytes)
}
