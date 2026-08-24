package com.androidbridge.relay

import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.cio.CIO
import io.ktor.server.engine.embeddedServer
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.plugins.statuspages.exception
import io.ktor.server.request.header
import io.ktor.server.request.receiveChannel
import io.ktor.server.request.uri
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.delete
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.server.websocket.WebSockets
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.WebSocketSession
import io.ktor.websocket.close
import io.ktor.websocket.readBytes
import io.ktor.websocket.send
import io.ktor.utils.io.readAvailable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.time.Clock
import kotlin.time.Duration.Companion.milliseconds

fun main() {
    val config = RelayConfig.fromEnvironment()
    embeddedServer(CIO, host = config.host, port = config.port) {
        relayModule(config, Clock.systemUTC(), SecureTokenSource(), Slf4jAuditSink())
    }.start(wait = true)
}

internal fun Application.relayModule(
    config: RelayConfig,
    clock: Clock,
    tokenSource: TokenSource,
    auditSink: AuditSink,
) {
    val json = Json { ignoreUnknownKeys = false; encodeDefaults = true }
    val store = ConfigStore(config.configPath, config.setupCode, config.setupTtlSeconds, clock)
    val enrollment = EnrollmentService(store, clock, tokenSource, config.invitationTtlSeconds)
    val auditor = Auditor(clock, auditSink)
    val registry = ConnectionRegistry(enrollment::peerOf, config.sendTimeoutMillis.milliseconds)

    install(ContentNegotiation) { json(json) }
    install(WebSockets) {
        maxFrameSize = config.maxFrameBytes
        masking = false
    }
    installSafeErrors(auditor)
    routing {
        get("/health") { call.respond(HealthResponse("ok")) }
        enrollmentRoutes(config, enrollment, registry, auditor, json)
        relaySocket(config, enrollment, registry, auditor, json)
    }
}

private fun Application.installSafeErrors(auditor: Auditor) {
    install(StatusPages) {
        exception<RelayException> { call, cause ->
            auditor.record("request_rejected", cause.code)
            call.respond(HttpStatusCode.fromValue(cause.status), ErrorResponse(cause.code))
        }
        exception<BadRequestException> { call, _ ->
            auditor.record("request_rejected", "invalid_request")
            call.respond(HttpStatusCode.BadRequest, ErrorResponse("invalid_request"))
        }
        exception<Throwable> { call, _ ->
            auditor.record("request_failed", "internal_error")
            call.respond(HttpStatusCode.InternalServerError, ErrorResponse("internal_error"))
        }
    }
}

private fun Route.enrollmentRoutes(
    config: RelayConfig,
    enrollment: EnrollmentService,
    registry: ConnectionRegistry,
    auditor: Auditor,
    json: Json,
) {
    route("/v1") {
        post("/enrollment/setup") {
            call.requireSecure(config)
            val request = call.receiveSmall<SetupEnrollmentRequest>(json)
            val response = enrollment.enrollSetup(request)
            auditor.record("setup_enrollment_succeeded", "created", request.deviceId)
            call.respond(HttpStatusCode.Created, response)
        }
        post("/enrollment/invitation") {
            call.requireSecure(config)
            val request = call.receiveSmall<InvitationEnrollmentRequest>(json)
            val response = enrollment.enrollInvitation(request)
            auditor.record("invitation_enrollment_succeeded", "created", request.deviceId)
            call.respond(HttpStatusCode.Created, response)
        }
        authenticatedRoutes(config, enrollment, registry, auditor, json)
    }
}

private fun Route.authenticatedRoutes(
    config: RelayConfig,
    enrollment: EnrollmentService,
    registry: ConnectionRegistry,
    auditor: Auditor,
    json: Json,
) {
    post("/invitations") {
        call.requireSecure(config)
        val device = call.authenticate(enrollment)
        val response = enrollment.createInvitation(device.deviceId, call.receiveSmall<InvitationRequest>(json))
        auditor.record("invitation_created", "created", device.deviceId)
        call.respond(HttpStatusCode.Created, response)
    }
    delete("/devices/{deviceId}") {
        call.requireSecure(config)
        val requester = call.authenticate(enrollment)
        val target = call.parameters["deviceId"] ?: throw RelayException(400, "invalid_device_id")
        enrollment.revoke(requester.deviceId, target)
        registry.disconnect(target)
        auditor.record("device_revoked", "revoked", target)
        call.respond(HttpStatusCode.NoContent)
    }
}

private fun Route.relaySocket(
    config: RelayConfig,
    enrollment: EnrollmentService,
    registry: ConnectionRegistry,
    auditor: Auditor,
    json: Json,
) {
    webSocket("/v1/connect") {
        val device = try {
            call.requireSecure(config)
            call.authenticate(enrollment)
        } catch (error: RelayException) {
            close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, error.code))
            return@webSocket
        }
        val connection = KtorRelayConnection(this)
        registry.register(device.deviceId, connection)
        auditor.record("device_connected", "connected", device.deviceId)
        try {
            routeFrames(device.deviceId, config, registry, auditor, json)
        } finally {
            registry.unregister(device.deviceId, connection)
            auditor.record("device_disconnected", "disconnected", device.deviceId)
        }
    }
}

private suspend fun io.ktor.server.websocket.DefaultWebSocketServerSession.routeFrames(
    deviceId: String,
    config: RelayConfig,
    registry: ConnectionRegistry,
    auditor: Auditor,
    json: Json,
) {
    for (frame in incoming) {
        if (frame !is Frame.Binary || !frame.fin) {
            close(CloseReason(CloseReason.Codes.CANNOT_ACCEPT, "binary_frames_only"))
            return
        }
        val payload = frame.readBytes()
        if (payload.size > config.maxFrameBytes) {
            close(CloseReason(CloseReason.Codes.TOO_BIG, "frame_too_large"))
            return
        }
        when (registry.forward(deviceId, payload)) {
            ForwardResult.FORWARDED -> auditor.record("frame_forwarded", "forwarded", deviceId, payload.size)
            ForwardResult.PEER_ABSENT -> sendError(json, "peer_absent")
            ForwardResult.BACKPRESSURE -> sendError(json, "peer_backpressure")
        }
    }
}

private suspend fun WebSocketSession.sendError(json: Json, code: String) {
    send(Frame.Text(json.encodeToString(ErrorResponse(code))))
}

private class KtorRelayConnection(private val session: WebSocketSession) : RelayConnection {
    override suspend fun send(payload: ByteArray) {
        session.send(Frame.Binary(true, payload))
    }

    override suspend fun close(reason: String) {
        session.close(CloseReason(CloseReason.Codes.NORMAL, reason))
    }
}

private fun io.ktor.server.application.ApplicationCall.authenticate(service: EnrollmentService): DeviceRecord =
    service.authenticate(request.header("X-Device-Id"), request.header(HttpHeaders.Authorization))

private fun io.ktor.server.application.ApplicationCall.requireSecure(config: RelayConfig) {
    if (config.requireTls && request.header("X-Forwarded-Proto") != "https") {
        throw RelayException(426, "tls_required")
    }
}

private suspend inline fun <reified T> io.ktor.server.application.ApplicationCall.receiveSmall(json: Json): T {
    val declaredLength = request.header(HttpHeaders.ContentLength)?.toLongOrNull()
    if (declaredLength != null && declaredLength > MAX_ENROLLMENT_BODY_BYTES) {
        throw RelayException(413, "request_too_large")
    }
    val input = receiveChannel()
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(1_024)
    while (!input.isClosedForRead) {
        val count = input.readAvailable(buffer)
        if (count <= 0) continue
        if (output.size() + count > MAX_ENROLLMENT_BODY_BYTES) throw RelayException(413, "request_too_large")
        output.write(buffer, 0, count)
    }
    return try {
        json.decodeFromString(output.toString(Charsets.UTF_8.name()))
    } catch (_: SerializationException) {
        throw BadRequestException("invalid_request")
    }
}

private const val MAX_ENROLLMENT_BODY_BYTES = 4_096
