package com.androidbridge.relay

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContain
import io.kotest.matchers.string.shouldNotContain
import io.ktor.client.request.post
import io.ktor.server.testing.testApplication

class SafeLoggingTest : FunSpec({
    test("audit logs contain event metadata but no secrets or request payload") {
        testApplication {
            val relay = installTestRelay()
            val client = jsonClient()
            val secretWorkspace = "workspace-payload-canary"
            val secretCode = "setup-secret"

            client.post("/v1/enrollment/setup") {
                jsonBody(SetupEnrollmentRequest(secretWorkspace, "mac-1", DeviceType.MAC, secretCode))
            }

            relay.auditSink.events.map { it.event } shouldContain "setup_enrollment_succeeded"
            val logs = relay.auditSink.events.joinToString("\n")
            logs shouldNotContain secretWorkspace
            logs shouldNotContain secretCode
        }
    }
})
