package com.androidbridge.relay

import com.androidbridge.core.SecureStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URI

@JvmInline
value class RelayEndpoint private constructor(val value: String) {
    val webSocketUrl: URI get() = URI(value)

    fun connectionUrl(): HttpUrl = HttpUrl.Builder()
        .scheme("https")
        .host(webSocketUrl.host)
        .port(if (webSocketUrl.port == -1) 443 else webSocketUrl.port)
        .encodedPath(webSocketUrl.rawPath.ifEmpty { "/" })
        .build()

    fun enrollmentUrl(): HttpUrl = connectionUrl().newBuilder().encodedPath("/v1/enroll").build()

    companion object {
        fun parse(raw: String): Result<RelayEndpoint> = runCatching {
            val value = raw.trim()
            require(value.length in 1..2_048) { "Relay endpoint is too long" }
            val uri = URI(value)
            require(uri.scheme == "wss") { "Relay endpoint must use wss://" }
            require(!uri.host.isNullOrBlank()) { "Relay endpoint must include a host" }
            require(uri.rawUserInfo == null) { "Relay endpoint must not contain credentials" }
            require(uri.rawQuery == null && uri.rawFragment == null) { "Relay endpoint must not contain query or fragment" }
            require(uri.port == -1 || uri.port in 1..65_535) { "Relay endpoint port is invalid" }
            RelayEndpoint(value)
        }
    }
}

@Serializable
data class RelayCredentials(val deviceId: String, val credential: String, val peerDeviceId: String)

data class RelaySettings(
    val enabled: Boolean,
    val endpoint: String,
    val credentials: RelayCredentials?,
)

data class RelaySettingsView(val enabled: Boolean, val endpoint: String, val enrolled: Boolean)

@Serializable
data class EnrollmentResult(val deviceId: String, val credential: String, val peerDeviceId: String)

class RelaySettingsRepository(private val store: SecureStore) {
    fun load(): RelaySettings {
        val deviceId = store.get(KEY_DEVICE_ID)
        val credential = store.get(KEY_CREDENTIAL)
        val peerDeviceId = store.get(KEY_PEER_ID)
        val credentials = if (deviceId != null && credential != null && peerDeviceId != null) {
            RelayCredentials(deviceId, credential, peerDeviceId)
        } else null
        return RelaySettings(store.get(KEY_ENABLED) == "true", store.get(KEY_ENDPOINT).orEmpty(), credentials)
    }

    fun saveEndpoint(endpoint: String) {
        val parsed = RelayEndpoint.parse(endpoint).getOrThrow()
        store.put(KEY_ENDPOINT, parsed.value)
    }

    fun saveEnrollment(result: EnrollmentResult) {
        require(result.deviceId.isNotBlank() && result.credential.isNotBlank() && result.peerDeviceId.isNotBlank())
        store.put(KEY_DEVICE_ID, result.deviceId)
        store.put(KEY_CREDENTIAL, result.credential)
        store.put(KEY_PEER_ID, result.peerDeviceId)
    }

    fun setEnabled(enabled: Boolean) = store.put(KEY_ENABLED, enabled.toString())

    fun clearCredentials() {
        store.delete(KEY_DEVICE_ID)
        store.delete(KEY_CREDENTIAL)
        store.delete(KEY_PEER_ID)
        setEnabled(false)
    }

    companion object {
        private const val KEY_ENABLED = "relay.enabled"
        private const val KEY_ENDPOINT = "relay.endpoint"
        private const val KEY_DEVICE_ID = "relay.deviceId"
        private const val KEY_CREDENTIAL = "relay.credential"
        private const val KEY_PEER_ID = "relay.peerDeviceId"
    }
}

class RelayEnrollmentClient(
    private val client: OkHttpClient = OkHttpClient(),
    private val json: Json = Json { ignoreUnknownKeys = false },
) {
    fun enroll(endpoint: RelayEndpoint, setupCode: String, deviceName: String): EnrollmentResult =
        enrollAt(endpoint.enrollmentUrl(), setupCode, deviceName)

    internal fun enrollAt(url: HttpUrl, setupCode: String, deviceName: String): EnrollmentResult {
        require(setupCode.length in 1..256) { "Setup code is required" }
        require(deviceName.length in 1..128) { "Device name is required" }
        val body = buildJsonObject {
            put("setupCode", setupCode)
            put("deviceName", deviceName)
            put("deviceRole", "android")
        }.toString().toRequestBody(JSON_MEDIA_TYPE)
        val request = Request.Builder().url(url).post(body).build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw RelayEnrollmentException(response.code)
            val responseBody = response.body ?: throw RelayEnrollmentException(response.code)
            if (responseBody.contentLength() > MAX_RESPONSE_BYTES) throw RelayEnrollmentException(response.code)
            val source = responseBody.source()
            if (source.request(MAX_RESPONSE_BYTES + 1L)) throw RelayEnrollmentException(response.code)
            val payload = json.parseToJsonElement(source.readUtf8()).jsonObject
            return EnrollmentResult(
                payload.getValue("deviceId").jsonPrimitive.content,
                payload.getValue("credential").jsonPrimitive.content,
                payload.getValue("peerDeviceId").jsonPrimitive.content,
            ).also {
                require(it.deviceId.length in 1..128 && it.peerDeviceId.length in 1..128)
                require(it.credential.length in 1..4_096)
            }
        }
    }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private const val MAX_RESPONSE_BYTES = 16_384
    }
}

class RelayEnrollmentException(val statusCode: Int) : Exception("Relay enrollment failed ($statusCode)")
