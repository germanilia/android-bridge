package com.androidbridge.core

import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.Date

/**
 * Generates a per-device self-signed EC certificate for mutual TLS (U2). The certificate fingerprint
 * (SHA-256 of the DER encoding) is what peers pin at pairing time — trust-on-first-use (SECURITY-06/-08).
 */
object CertFactory {

    data class Identity(val keyPair: KeyPair, val certificate: X509Certificate) {
        val fingerprint: String get() = sha256Hex(certificate.encoded)
    }

    fun generateSelfSigned(commonName: String): Identity {
        val kpg = KeyPairGenerator.getInstance("EC").apply { initialize(256) }
        val kp = kpg.generateKeyPair()
        val now = System.currentTimeMillis()
        val notBefore = Date(now - 60_000)
        val notAfter = Date(now + 3650L * 24 * 3600 * 1000) // ~10 years
        val name = X500Name("CN=$commonName")
        val builder = JcaX509v3CertificateBuilder(name, BigInteger.valueOf(now), notBefore, notAfter, name, kp.public)
        val signer = JcaContentSignerBuilder("SHA256withECDSA").build(kp.private)
        val cert = JcaX509CertificateConverter().getCertificate(builder.build(signer))
        return Identity(kp, cert)
    }

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(":") { "%02x".format(it) }
}
