package com.androidbridge.relay

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.booleans.shouldBeFalse
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldNotContain
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.http.HttpStatusCode
import io.ktor.server.testing.testApplication
import kotlin.io.path.readText

class EnrollmentIntegrationTest : FunSpec({
    test("setup enrollment is one-time and persists only token hashes") {
        testApplication {
            val relay = installTestRelay()
            val client = jsonClient()
            val request = SetupEnrollmentRequest("home", "mac-1", DeviceType.MAC, "setup-secret")

            val first = client.post("/v1/enrollment/setup") { jsonBody(request) }
            first.status shouldBe HttpStatusCode.Created
            val credential = first.decoded<CredentialResponse>().credential

            client.post("/v1/enrollment/setup") { jsonBody(request.copy(deviceId = "mac-2")) }.status shouldBe
                HttpStatusCode.Conflict
            val persisted = relay.configPath.readText()
            persisted shouldNotContain "setup-secret"
            persisted shouldNotContain credential
            persisted.contains(TokenHasher.hash(credential)) shouldBe true
        }
    }

    test("an enrolled Mac issues a one-time phone invitation") {
        testApplication {
            val relay = installTestRelay()
            val client = jsonClient()
            val mac = enrollMac(client)

            val inviteResponse = client.post("/v1/invitations") {
                auth("mac-1", mac.credential)
                jsonBody(InvitationRequest(DeviceType.PHONE))
            }
            inviteResponse.status shouldBe HttpStatusCode.Created
            val invitation = inviteResponse.decoded<InvitationResponse>().invitation
            val phoneRequest = InvitationEnrollmentRequest("phone-1", invitation)
            val phone = client.post("/v1/enrollment/invitation") { jsonBody(phoneRequest) }
            phone.status shouldBe HttpStatusCode.Created
            val phoneCredential = phone.decoded<CredentialResponse>().credential

            client.post("/v1/enrollment/invitation") { jsonBody(phoneRequest.copy(deviceId = "phone-2")) }.status shouldBe
                HttpStatusCode.Conflict
            val persisted = relay.configPath.readText()
            persisted shouldNotContain invitation
            persisted shouldNotContain phoneCredential
            persisted.contains(TokenHasher.hash(invitation)) shouldBe true
        }
    }

    test("paired device can revoke its peer credential") {
        testApplication {
            installTestRelay()
            val client = jsonClient()
            val pair = enrollPair(client)

            client.delete("/v1/devices/phone-1") { auth("mac-1", pair.macCredential) }.status shouldBe
                HttpStatusCode.NoContent
            client.post("/v1/invitations") {
                auth("phone-1", pair.phoneCredential)
                jsonBody(InvitationRequest(DeviceType.MAC))
            }.status shouldBe HttpStatusCode.Unauthorized
        }
    }

    test("health is public and contains no configuration state") {
        testApplication {
            installTestRelay()
            val response = jsonClient().get("/health")
            response.status shouldBe HttpStatusCode.OK
            val body = response.decoded<HealthResponse>()
            body shouldBe HealthResponse("ok")
            body.toString().contains("workspace").shouldBeFalse()
        }
    }
})

internal data class EnrolledPair(val macCredential: String, val phoneCredential: String)

internal suspend fun enrollMac(client: io.ktor.client.HttpClient): CredentialResponse =
    client.post("/v1/enrollment/setup") {
        jsonBody(SetupEnrollmentRequest("home", "mac-1", DeviceType.MAC, "setup-secret"))
    }.decoded()

internal suspend fun enrollPair(client: io.ktor.client.HttpClient): EnrolledPair {
    val mac = enrollMac(client)
    val invitation = client.post("/v1/invitations") {
        auth("mac-1", mac.credential)
        jsonBody(InvitationRequest(DeviceType.PHONE))
    }.decoded<InvitationResponse>()
    val phone = client.post("/v1/enrollment/invitation") {
        jsonBody(InvitationEnrollmentRequest("phone-1", invitation.invitation))
    }.decoded<CredentialResponse>()
    return EnrolledPair(mac.credential, phone.credential)
}
