package com.androidbridge.relay

enum class RelayRoute { NONE, DIRECT, RELAY }

enum class RelayConnectionState {
    DISABLED,
    ENROLLMENT_REQUIRED,
    SEARCHING_DIRECT,
    CONNECTING_RELAY,
    DIRECT_CONNECTED,
    RELAY_CONNECTED,
    RECONNECTING,
    PAUSED,
    ERROR,
}

data class RelayUiStatus(val state: RelayConnectionState, val message: String = "")

/** Rejects callbacks from old connection attempts and guarantees one active route. */
class DirectFirstSessionGate {
    @Volatile
    var generation: Long = 0
        private set
    @Volatile
    var route: RelayRoute = RelayRoute.NONE
        private set

    @Synchronized
    fun beginAttempt(): Long {
        generation++
        route = RelayRoute.NONE
        return generation
    }

    @Synchronized
    fun adopt(candidateGeneration: Long, candidate: RelayRoute): Boolean {
        if (candidateGeneration != generation || candidate == RelayRoute.NONE) return false
        if (route == RelayRoute.DIRECT && candidate == RelayRoute.RELAY) return false
        if (route == candidate) return true
        route = candidate
        return true
    }

    @Synchronized
    fun invalidate(candidateGeneration: Long): Boolean {
        if (candidateGeneration != generation) return false
        generation++
        route = RelayRoute.NONE
        return true
    }

    @Synchronized
    fun currentGeneration(): Long = generation
}

class RelayReconnectBackoff(
    private val minimumMs: Long = 1_000,
    private val maximumMs: Long = 30_000,
    private val random: () -> Double = { kotlin.random.Random.nextDouble() },
) {
    fun delayMs(attempt: Int): Long {
        require(attempt >= 0)
        val multiplier = 1L shl attempt.coerceAtMost(20)
        val base = (minimumMs * multiplier).coerceAtMost(maximumMs)
        val jittered = (base * (0.8 + random() * 0.4)).toLong()
        return jittered.coerceIn((minimumMs * 0.8).toLong(), maximumMs)
    }
}
