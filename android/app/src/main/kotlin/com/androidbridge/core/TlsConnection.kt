package com.androidbridge.core

import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import java.io.DataInputStream
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager

/**
 * Mutual-TLS transport (U3). Establishes a mTLS session against a pinned peer certificate and carries
 * length-prefixed protocol messages. Rejecting an unpinned peer happens at the TLS layer (CC-SEC).
 * Pure JVM/javax.net.ssl so it is integration-testable in-process (localhost loopback).
 */
object TlsLink {
    private val KEYSTORE_PASSWORD = "android_bridge".toCharArray()

    /** Trust manager that accepts a peer cert only if its SHA-256 fingerprint is pinned. */
    private class PinnedTrustManager(private val isPinned: (String) -> Boolean) : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) = verify(chain)
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) = verify(chain)
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        private fun verify(chain: Array<out X509Certificate>) {
            val fp = CertFactory.sha256Hex(chain.first().encoded)
            if (!isPinned(fp)) {
                LinkLogger.securityEvent("tls_pin_reject")
                throw CertificateException("unpinned peer certificate")
            }
        }
    }

    private fun sslContext(identity: CertFactory.Identity, isPinned: (String) -> Boolean): SSLContext {
        val ks = KeyStore.getInstance("PKCS12").apply {
            load(null, null)
            setKeyEntry("key", identity.keyPair.private, KEYSTORE_PASSWORD, arrayOf(identity.certificate))
        }
        val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply {
            init(ks, KEYSTORE_PASSWORD)
        }
        return SSLContext.getInstance("TLS").apply {
            init(kmf.keyManagers, arrayOf(PinnedTrustManager(isPinned)), SecureRandom())
        }
    }

    /** A connected mTLS session that reads/writes length-prefixed protocol messages. */
    class Session(private val socket: SSLSocket) {
        private val input = DataInputStream(socket.inputStream)
        private val output = socket.outputStream

        fun send(message: Message) {
            output.write(MessageCodec.encode(message))
            output.flush()
        }

        fun receive(): Message {
            val header = ByteArray(4)
            input.readFully(header)
            val len = ((header[0].toInt() and 0xFF) shl 24) or ((header[1].toInt() and 0xFF) shl 16) or
                ((header[2].toInt() and 0xFF) shl 8) or (header[3].toInt() and 0xFF)
            val body = ByteArray(len)
            input.readFully(body)
            return MessageCodec.decode(header + body)
        }

        fun close() = socket.close()
    }

    /** Open a TLS server socket. When [requireClientAuth] is false this is server-authenticated TLS. */
    fun openServer(identity: CertFactory.Identity, port: Int = 0, requireClientAuth: Boolean = true, isPinned: (String) -> Boolean): SSLServerSocket {
        val server = sslContext(identity, isPinned).serverSocketFactory.createServerSocket(port) as SSLServerSocket
        server.needClientAuth = requireClientAuth
        return server
    }

    fun openServer(identity: CertFactory.Identity, port: Int = 0): SSLServerSocket =
        openServer(identity, port, requireClientAuth = false) { true }

    /** Convenience: open a server pinned to exactly one peer fingerprint. */
    fun openServer(identity: CertFactory.Identity, pinnedPeerFingerprint: String, port: Int = 0): SSLServerSocket =
        openServer(identity, port, requireClientAuth = true) { it == pinnedPeerFingerprint }

    /** Accept one incoming mTLS connection and complete the handshake (throws if the peer is unpinned). */
    fun accept(server: SSLServerSocket): Session {
        val socket = server.accept() as SSLSocket
        socket.startHandshake()
        return Session(socket)
    }

    /** Connect to a pinned peer over mTLS (throws if the peer is unpinned). */
    fun connect(host: String, port: Int, identity: CertFactory.Identity, pinnedPeerFingerprint: String): Session {
        val socket = sslContext(identity) { it == pinnedPeerFingerprint }.socketFactory.createSocket(host, port) as SSLSocket
        socket.startHandshake()
        return Session(socket)
    }
}
