package com.androidbridge.relay

import org.slf4j.LoggerFactory
import java.time.Clock
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

internal data class AuditEvent(
    val timestamp: Instant,
    val requestId: String,
    val event: String,
    val deviceId: String? = null,
    val result: String,
    val byteCount: Int? = null,
)

internal fun interface AuditSink {
    fun record(event: AuditEvent)
}

internal class Slf4jAuditSink : AuditSink {
    private val logger = LoggerFactory.getLogger("relay.audit")

    override fun record(event: AuditEvent) {
        logger.info(
            "timestamp={} request_id={} event={} device_id={} result={} byte_count={}",
            event.timestamp, event.requestId, event.event, event.deviceId ?: "-", event.result, event.byteCount ?: 0,
        )
    }
}

internal class RecordingAuditSink : AuditSink {
    val events = CopyOnWriteArrayList<AuditEvent>()
    override fun record(event: AuditEvent) { events += event }
}

internal class Auditor(private val clock: Clock, private val sink: AuditSink) {
    fun record(event: String, result: String, deviceId: String? = null, byteCount: Int? = null) {
        sink.record(AuditEvent(clock.instant(), UUID.randomUUID().toString(), event, deviceId, result, byteCount))
    }
}
