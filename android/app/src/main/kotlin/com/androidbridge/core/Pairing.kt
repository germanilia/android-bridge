package com.androidbridge.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

private val pairingJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/** This device's stable identity. The private key is held in [SecureStore]; only public material travels. */
@Serializable
data class DeviceIdentity(
    val deviceId: String,
    val deviceName: String,
    val publicKeyB64: String,
)

/** A peer this device trusts (pinned at pairing time — trust-on-first-use). */
@Serializable
data class PairedDevice(
    val deviceId: String,
    val deviceName: String,
    val publicKeyB64: String,
    val fingerprint: String,
    val host: String = "",
    val port: Int = 0,
)

/** The payload encoded into the pairing QR code. */
@Serializable
data class QrPayload(
    val deviceId: String,
    val deviceName: String,
    val publicKeyB64: String,
    val fingerprint: String,
    val host: String,
    val port: Int,
)

/**
 * Pairing & trust (U2). Generates a per-device keypair, builds/consumes pairing QR payloads, and
 * pins peers via [SecureStore]. Crypto uses the JDK (EC P-256) so the logic is JVM-testable;
 * full X.509/mTLS wiring is layered on top by the connection unit.
 */
class PairingManager(private val store: SecureStore) {

    fun fingerprintOf(publicKeyB64: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(Base64.getDecoder().decode(publicKeyB64))
        return digest.joinToString(":") { "%02x".format(it) }
    }

    fun generateIdentity(deviceName: String): DeviceIdentity {
        val kpg = KeyPairGenerator.getInstance("EC").apply { initialize(256) }
        val kp = kpg.generateKeyPair()
        val pubB64 = Base64.getEncoder().encodeToString(kp.public.encoded)
        val privB64 = Base64.getEncoder().encodeToString(kp.private.encoded)
        val identity = DeviceIdentity(deviceId = UUID.randomUUID().toString(), deviceName = deviceName, publicKeyB64 = pubB64)
        store.put(KEY_IDENTITY, pairingJson.encodeToString(DeviceIdentity.serializer(), identity))
        store.put(KEY_PRIVATE, privB64)
        return identity
    }

    fun loadIdentity(): DeviceIdentity? =
        store.get(KEY_IDENTITY)?.let { pairingJson.decodeFromString(DeviceIdentity.serializer(), it) }

    fun createPairingQr(identity: DeviceIdentity, host: String, port: Int): String {
        val payload = QrPayload(
            deviceId = identity.deviceId,
            deviceName = identity.deviceName,
            publicKeyB64 = identity.publicKeyB64,
            fingerprint = fingerprintOf(identity.publicKeyB64),
            host = host,
            port = port,
        )
        return pairingJson.encodeToString(QrPayload.serializer(), payload)
    }

    /** Parse + pin a scanned QR payload (trust-on-first-use). Returns the pinned peer. */
    fun consumePairingQr(qr: String): PairedDevice {
        val payload = pairingJson.decodeFromString(QrPayload.serializer(), qr)
        val expected = fingerprintOf(payload.publicKeyB64)
        if (expected != payload.fingerprint) {
            LinkLogger.securityEvent("pair_fingerprint_mismatch", mapOf("deviceId" to payload.deviceId))
            throw IllegalArgumentException("fingerprint mismatch")
        }
        val peer = PairedDevice(
            deviceId = payload.deviceId,
            deviceName = payload.deviceName,
            publicKeyB64 = payload.publicKeyB64,
            fingerprint = payload.fingerprint,
            host = payload.host,
            port = payload.port,
        )
        pinPeer(peer)
        return peer
    }

    fun pinPeer(peer: PairedDevice) {
        val list = listPaired().filter { it.deviceId != peer.deviceId } + peer
        store.put(KEY_PAIRED, pairingJson.encodeToString(PairedListSurrogate.serializer(), PairedListSurrogate(list)))
        LinkLogger.info("peer_pinned", mapOf("deviceId" to peer.deviceId))
    }

    fun listPaired(): List<PairedDevice> =
        store.get(KEY_PAIRED)?.let {
            pairingJson.decodeFromString(PairedListSurrogate.serializer(), it).devices
        } ?: emptyList()

    fun unpair(deviceId: String) {
        val list = listPaired().filter { it.deviceId != deviceId }
        store.put(KEY_PAIRED, pairingJson.encodeToString(PairedListSurrogate.serializer(), PairedListSurrogate(list)))
        LinkLogger.info("peer_unpaired", mapOf("deviceId" to deviceId))
    }

    fun isPinned(fingerprint: String): Boolean = listPaired().any { it.fingerprint == fingerprint }

    @Serializable
    private data class PairedListSurrogate(val devices: List<PairedDevice>)

    companion object {
        private const val KEY_IDENTITY = "identity"
        private const val KEY_PRIVATE = "identity.private"
        private const val KEY_PAIRED = "paired.devices"
    }
}
