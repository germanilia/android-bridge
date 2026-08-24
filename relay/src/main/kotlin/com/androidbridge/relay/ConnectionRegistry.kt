package com.androidbridge.relay

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.time.Duration

internal interface RelayConnection {
    suspend fun send(payload: ByteArray)
    suspend fun close(reason: String)
}

internal enum class ForwardResult { FORWARDED, PEER_ABSENT, BACKPRESSURE }

internal class ConnectionRegistry(
    private val peerResolver: (String) -> String?,
    private val sendTimeout: Duration,
) {
    private val mutex = Mutex()
    private val connections = mutableMapOf<String, RelayConnection>()

    suspend fun register(deviceId: String, connection: RelayConnection) {
        val replaced = mutex.withLock { connections.put(deviceId, connection) }
        replaced?.close("replaced")
    }

    suspend fun unregister(deviceId: String, connection: RelayConnection) {
        mutex.withLock {
            if (connections[deviceId] === connection) connections.remove(deviceId)
        }
    }

    suspend fun disconnect(deviceId: String) {
        val connection = mutex.withLock { connections.remove(deviceId) }
        connection?.close("revoked")
    }

    suspend fun forward(senderId: String, payload: ByteArray): ForwardResult {
        val peerId = peerResolver(senderId) ?: return ForwardResult.PEER_ABSENT
        val peer = mutex.withLock { connections[peerId] } ?: return ForwardResult.PEER_ABSENT
        return try {
            if (withTimeoutOrNull(sendTimeout) { peer.send(payload) } == null) ForwardResult.BACKPRESSURE
            else ForwardResult.FORWARDED
        } catch (_: Exception) {
            unregister(peerId, peer)
            ForwardResult.PEER_ABSENT
        }
    }

    suspend fun isCurrent(deviceId: String, connection: RelayConnection): Boolean =
        mutex.withLock { connections[deviceId] === connection }
}
