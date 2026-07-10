package com.androidbridge.core

import java.io.ByteArrayInputStream
import java.security.KeyFactory
import java.security.KeyPair
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64

/**
 * Loads or creates the device's persistent mutual-TLS identity (U2). The same self-signed cert is used
 * both as the pairing identity (its SHA-256 fingerprint is what peers pin) and for the mTLS handshake,
 * so pairing and the transport share one trust anchor. Private key + cert are stored encrypted at rest.
 */
object CertIdentityStore {
    private const val KEY_CERT = "identity.cert"
    private const val KEY_PRIVATE = "identity.key"

    fun loadOrCreate(store: SecureStore, deviceName: String): CertFactory.Identity {
        val certB64 = store.get(KEY_CERT)
        val keyB64 = store.get(KEY_PRIVATE)
        if (certB64 != null && keyB64 != null) {
            val cert = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(Base64.getDecoder().decode(certB64))) as X509Certificate
            val key = KeyFactory.getInstance("EC")
                .generatePrivate(PKCS8EncodedKeySpec(Base64.getDecoder().decode(keyB64)))
            return CertFactory.Identity(KeyPair(cert.publicKey, key), cert)
        }
        val identity = CertFactory.generateSelfSigned(deviceName)
        store.put(KEY_CERT, Base64.getEncoder().encodeToString(identity.certificate.encoded))
        store.put(KEY_PRIVATE, Base64.getEncoder().encodeToString(identity.keyPair.private.encoded))
        return identity
    }
}
