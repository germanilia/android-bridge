package com.androidbridge.relay

import java.time.Clock
import java.time.Instant

internal class RelayException(val status: Int, val code: String) : RuntimeException(code)

internal class EnrollmentService(
    private val store: ConfigStore,
    private val clock: Clock,
    private val tokens: TokenSource,
    private val invitationTtlSeconds: Long,
) {
    suspend fun enrollSetup(request: SetupEnrollmentRequest): CredentialResponse {
        validateId(request.workspaceId, "workspace_id")
        validateId(request.deviceId, "device_id")
        requireRelay(request.deviceType == DeviceType.MAC, 400, "setup_device_must_be_mac")
        val credential = tokens.create("cred_")
        store.update { state -> setupEnrollment(state, request, credential) }
        return CredentialResponse(request.deviceId, credential)
    }

    suspend fun createInvitation(deviceId: String, request: InvitationRequest): InvitationResponse {
        val invitation = tokens.create("invite_")
        val expiresAt = clock.instant().plusSeconds(invitationTtlSeconds)
        store.update { state -> addInvitation(state, deviceId, request, invitation, expiresAt) }
        return InvitationResponse(invitation, expiresAt.toString())
    }

    suspend fun enrollInvitation(request: InvitationEnrollmentRequest): CredentialResponse {
        validateId(request.deviceId, "device_id")
        requireRelay(request.invitation.length in 16..256, 400, "invalid_invitation")
        val credential = tokens.create("cred_")
        store.update { state -> invitationEnrollment(state, request, credential) }
        return CredentialResponse(request.deviceId, credential)
    }

    suspend fun revoke(requesterId: String, targetId: String) {
        validateId(targetId, "device_id")
        store.update { state -> revokeDevice(state, requesterId, targetId) }
    }

    fun authenticate(deviceId: String?, authorization: String?): DeviceRecord {
        validateId(deviceId ?: throw RelayException(401, "unauthorized"), "device_id")
        val token = authorization?.takeIf { it.startsWith("Bearer ") }?.removePrefix("Bearer ")
            ?: throw RelayException(401, "unauthorized")
        val device = store.snapshot().devices[deviceId] ?: throw RelayException(401, "unauthorized")
        requireRelay(!device.revoked && TokenHasher.matches(token, device.credentialHash), 401, "unauthorized")
        return device
    }

    fun peerOf(deviceId: String): String? = store.snapshot().devices[deviceId]
        ?.takeUnless(DeviceRecord::revoked)?.peerDeviceId
        ?.takeIf { store.snapshot().devices[it]?.revoked == false }

    private fun setupEnrollment(state: RelayState, request: SetupEnrollmentRequest, credential: String): RelayState {
        requireRelay(!state.setup.consumed, 409, "setup_already_consumed")
        requireRelay(clock.instant().epochSecond <= state.setup.expiresAtEpochSeconds, 410, "setup_expired")
        requireRelay(TokenHasher.matches(request.setupCode, state.setup.tokenHash), 401, "invalid_setup_code")
        requireRelay(request.deviceId !in state.devices, 409, "device_exists")
        val device = DeviceRecord(request.deviceId, request.workspaceId, request.deviceType, TokenHasher.hash(credential))
        return state.copy(setup = state.setup.copy(consumed = true), devices = state.devices + (request.deviceId to device))
    }

    private fun addInvitation(
        state: RelayState,
        inviterId: String,
        request: InvitationRequest,
        invitation: String,
        expiresAt: Instant,
    ): RelayState {
        val inviter = activeDevice(state, inviterId)
        requireRelay(inviter.peerDeviceId == null, 409, "device_already_paired")
        requireRelay(inviter.deviceType != request.deviceType, 400, "peer_type_must_differ")
        val record = InvitationRecord(
            TokenHasher.hash(invitation), inviter.workspaceId, inviterId, request.deviceType, expiresAt.epochSecond,
        )
        return state.copy(invitations = state.invitations + (record.tokenHash to record))
    }

    private fun invitationEnrollment(
        state: RelayState,
        request: InvitationEnrollmentRequest,
        credential: String,
    ): RelayState {
        val hash = TokenHasher.hash(request.invitation)
        val invitation = state.invitations.values.firstOrNull { TokenHasher.matches(request.invitation, it.tokenHash) }
            ?: throw RelayException(401, "invalid_invitation")
        requireRelay(!invitation.consumed, 409, "invitation_already_consumed")
        requireRelay(clock.instant().epochSecond <= invitation.expiresAtEpochSeconds, 410, "invitation_expired")
        requireRelay(request.deviceId !in state.devices, 409, "device_exists")
        val inviter = activeDevice(state, invitation.inviterDeviceId)
        requireRelay(inviter.peerDeviceId == null, 409, "device_already_paired")
        val peer = DeviceRecord(
            request.deviceId, invitation.workspaceId, invitation.deviceType, TokenHasher.hash(credential), inviter.deviceId,
        )
        val devices = state.devices + (inviter.deviceId to inviter.copy(peerDeviceId = peer.deviceId)) + (peer.deviceId to peer)
        return state.copy(devices = devices, invitations = state.invitations + (hash to invitation.copy(consumed = true)))
    }

    private fun revokeDevice(state: RelayState, requesterId: String, targetId: String): RelayState {
        val requester = activeDevice(state, requesterId)
        val target = state.devices[targetId] ?: throw RelayException(404, "device_not_found")
        requireRelay(target.workspaceId == requester.workspaceId, 404, "device_not_found")
        requireRelay(targetId == requesterId || requester.peerDeviceId == targetId, 403, "forbidden")
        val devices = state.devices.toMutableMap()
        devices[targetId] = target.copy(revoked = true, peerDeviceId = null)
        target.peerDeviceId?.let { peerId -> devices[peerId]?.let { devices[peerId] = it.copy(peerDeviceId = null) } }
        return state.copy(devices = devices)
    }

    private fun activeDevice(state: RelayState, id: String): DeviceRecord = state.devices[id]
        ?.takeUnless(DeviceRecord::revoked) ?: throw RelayException(401, "unauthorized")
}

private val validId = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,63}")

internal fun validateId(value: String, field: String) {
    requireRelay(validId.matches(value), 400, "invalid_$field")
}

internal fun requireRelay(condition: Boolean, status: Int, code: String) {
    if (!condition) throw RelayException(status, code)
}
