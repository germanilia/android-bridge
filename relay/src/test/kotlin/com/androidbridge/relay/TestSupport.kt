package com.androidbridge.relay

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.testing.ApplicationTestBuilder
import kotlinx.serialization.json.Json
import java.nio.file.Path
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.io.path.createTempDirectory

internal val testJson = Json { ignoreUnknownKeys = false }

internal data class TestRelay(
    val configPath: Path,
    val clock: Clock = Clock.fixed(Instant.parse("2026-08-24T12:00:00Z"), ZoneOffset.UTC),
    val tokens: QueueTokenSource = QueueTokenSource(),
    val auditSink: RecordingAuditSink = RecordingAuditSink(),
)

internal fun ApplicationTestBuilder.installTestRelay(
    maxFrameBytes: Long = 1_024,
    relay: TestRelay = TestRelay(createTempDirectory().resolve("relay-config.json")),
): TestRelay {
    application {
        relayModule(
            RelayConfig(
                host = "127.0.0.1",
                port = 8080,
                configPath = relay.configPath,
                setupCode = "setup-secret",
                setupTtlSeconds = 300,
                invitationTtlSeconds = 300,
                maxFrameBytes = maxFrameBytes,
                sendTimeoutMillis = 100,
                requireTls = false,
            ),
            relay.clock,
            relay.tokens,
            relay.auditSink,
        )
    }
    return relay
}

internal fun ApplicationTestBuilder.jsonClient(): HttpClient = createClient {
    install(ContentNegotiation) { json(testJson) }
}

internal fun HttpRequestBuilder.auth(deviceId: String, credential: String) {
    header("X-Device-Id", deviceId)
    header(HttpHeaders.Authorization, "Bearer $credential")
}

internal fun HttpRequestBuilder.jsonBody(value: Any) {
    contentType(ContentType.Application.Json)
    setBody(value)
}

internal suspend inline fun <reified T> io.ktor.client.statement.HttpResponse.decoded(): T = body()
