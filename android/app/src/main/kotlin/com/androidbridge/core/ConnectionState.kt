package com.androidbridge.core

/** Link lifecycle states surfaced to the UI (FR-2.3). */
enum class ConnectionState { DISCONNECTED, DISCOVERING, CONNECTING, CONNECTED, RECONNECTING }

/**
 * Pure state machine for the connection lifecycle (auto-reconnect, FR-2.4). The transport layer
 * drives [onEvent]; the UI observes [state]. Kept side-effect-free so it is JVM-testable.
 */
class ConnectionStateMachine(initial: ConnectionState = ConnectionState.DISCONNECTED) {
    var state: ConnectionState = initial
        private set

    enum class Event { START_DISCOVERY, PEER_FOUND, CONNECTED, LINK_DROPPED, DISCONNECT_REQUESTED }

    fun onEvent(event: Event): ConnectionState {
        state = when (event) {
            Event.START_DISCOVERY -> ConnectionState.DISCOVERING
            Event.PEER_FOUND -> if (state == ConnectionState.DISCOVERING || state == ConnectionState.RECONNECTING)
                ConnectionState.CONNECTING else state
            Event.CONNECTED -> ConnectionState.CONNECTED
            Event.LINK_DROPPED -> if (state == ConnectionState.CONNECTED) ConnectionState.RECONNECTING else state
            Event.DISCONNECT_REQUESTED -> ConnectionState.DISCONNECTED
        }
        return state
    }
}
