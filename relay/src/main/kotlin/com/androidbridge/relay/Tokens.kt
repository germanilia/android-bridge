package com.androidbridge.relay

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.atomic.AtomicInteger

internal object TokenHasher {
    fun hash(token: String): String = MessageDigest.getInstance("SHA-256")
        .digest(token.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

    fun matches(token: String, expectedHash: String): Boolean = MessageDigest.isEqual(
        hash(token).toByteArray(Charsets.US_ASCII),
        expectedHash.toByteArray(Charsets.US_ASCII),
    )
}

internal fun interface TokenSource {
    fun create(prefix: String): String
}

internal class SecureTokenSource(private val random: SecureRandom = SecureRandom()) : TokenSource {
    override fun create(prefix: String): String {
        val bytes = ByteArray(32)
        random.nextBytes(bytes)
        return prefix + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }
}

internal class QueueTokenSource : TokenSource {
    private val sequence = AtomicInteger()
    override fun create(prefix: String): String = prefix + sequence.incrementAndGet().toString().padStart(4, '0') + "-test-token"
}
