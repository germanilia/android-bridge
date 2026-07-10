package com.androidbridge.core

import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageTypes
import com.androidbridge.protocol.validate

/**
 * Dispatches validated inbound messages to the plugin registered for their `type`.
 * Fail-closed: unknown/invalid messages are dropped + logged, never crash (SECURITY-15).
 */
class MessageRouter {
    private val handlers = HashMap<String, (Message) -> Unit>()

    fun register(type: String, handler: (Message) -> Unit) {
        require(type in MessageTypes.known) { "cannot register unknown type: $type" }
        handlers[type] = handler
    }

    fun unregister(type: String) {
        handlers.remove(type)
    }

    fun registeredTypes(): Set<String> = handlers.keys.toSet()

    /**
     * Route a decoded message. Returns true if it was dispatched, false if dropped.
     * (Decoding/validation already happened in the codec; this re-checks defensively.)
     */
    fun route(message: Message): Boolean {
        val vr = validate(message)
        if (!vr.valid) {
            LinkLogger.securityEvent("dropped_invalid", mapOf("type" to message.type, "reason" to vr.code!!.name))
            return false
        }
        val handler = handlers[message.type]
        if (handler == null) {
            LinkLogger.securityEvent("dropped_unrouted", mapOf("type" to message.type))
            return false
        }
        handler(message)
        return true
    }
}
