package com.androidbridge.core

/**
 * Structured logging that never records message bodies, phone numbers, contacts, or tokens
 * (CC-PRIV / SECURITY-03). Only safe fields: event name, level, and a small allow-listed field map.
 */
object LinkLogger {
    enum class Level { DEBUG, INFO, WARN, ERROR }

    /** Field keys that must never be logged even if a caller passes them. */
    private val FORBIDDEN = setOf("body", "text", "number", "address", "contact", "token", "payload", "message")

    var sink: (Level, String, Map<String, String>) -> Unit = { level, event, fields ->
        println("[$level] $event ${fields.entries.joinToString(",") { "${it.key}=${it.value}" }}")
    }

    fun log(level: Level, event: String, fields: Map<String, String> = emptyMap()) {
        val safe = fields.filterKeys { it.lowercase() !in FORBIDDEN }
        sink(level, event, safe)
    }

    fun info(event: String, fields: Map<String, String> = emptyMap()) = log(Level.INFO, event, fields)
    fun warn(event: String, fields: Map<String, String> = emptyMap()) = log(Level.WARN, event, fields)

    /** Security-relevant events (failed pairing/auth, dropped malformed messages) — SECURITY-14. */
    fun securityEvent(event: String, fields: Map<String, String> = emptyMap()) =
        log(Level.WARN, "security.$event", fields)

    /** Redact a map for safe logging (drops forbidden keys). */
    fun redact(fields: Map<String, String>): Map<String, String> =
        fields.filterKeys { it.lowercase() !in FORBIDDEN }
}
