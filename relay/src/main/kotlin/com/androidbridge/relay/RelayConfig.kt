package com.androidbridge.relay

import java.nio.file.Path

internal data class RelayConfig(
    val host: String,
    val port: Int,
    val configPath: Path,
    val setupCode: String,
    val setupTtlSeconds: Long,
    val invitationTtlSeconds: Long,
    val maxFrameBytes: Long,
    val sendTimeoutMillis: Long,
    val requireTls: Boolean,
) {
    companion object {
        fun fromEnvironment(env: Map<String, String> = System.getenv()): RelayConfig {
            val setupCode = required(env, "RELAY_SETUP_CODE")
            require(setupCode.length >= 16) { "RELAY_SETUP_CODE must contain at least 16 characters" }
            return RelayConfig(
                host = env["RELAY_HOST"] ?: "0.0.0.0",
                port = integer(env, "RELAY_PORT", 8080, 1..65535),
                configPath = Path.of(env["RELAY_CONFIG_PATH"] ?: "/config/relay-config.json"),
                setupCode = setupCode,
                setupTtlSeconds = long(env, "RELAY_SETUP_TTL_SECONDS", 900, 60L..86_400L),
                invitationTtlSeconds = long(env, "RELAY_INVITATION_TTL_SECONDS", 600, 60L..86_400L),
                maxFrameBytes = long(env, "RELAY_MAX_FRAME_BYTES", 1_048_576, 1_024L..16_777_216L),
                sendTimeoutMillis = long(env, "RELAY_SEND_TIMEOUT_MILLIS", 5_000, 100L..60_000L),
                requireTls = boolean(env, "RELAY_REQUIRE_TLS", true),
            )
        }

        private fun required(env: Map<String, String>, name: String): String =
            env[name]?.takeIf(String::isNotBlank) ?: error("$name is required")

        private fun integer(env: Map<String, String>, name: String, default: Int, range: IntRange): Int =
            (env[name]?.toIntOrNull() ?: default).also { require(it in range) { "$name is out of range" } }

        private fun long(env: Map<String, String>, name: String, default: Long, range: LongRange): Long =
            (env[name]?.toLongOrNull() ?: default).also { require(it in range) { "$name is out of range" } }

        private fun boolean(env: Map<String, String>, name: String, default: Boolean): Boolean =
            env[name]?.let { require(it == "true" || it == "false") { "$name must be true or false" }; it.toBoolean() } ?: default
    }
}
