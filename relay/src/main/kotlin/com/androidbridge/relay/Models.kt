package com.androidbridge.relay

import kotlinx.serialization.Serializable

@Serializable
enum class DeviceType { MAC, PHONE }

@Serializable
data class SetupEnrollmentRequest(
    val workspaceId: String,
    val deviceId: String,
    val deviceType: DeviceType,
    val setupCode: String,
)

@Serializable
data class InvitationRequest(val deviceType: DeviceType)

@Serializable
data class InvitationEnrollmentRequest(val deviceId: String, val invitation: String)

@Serializable
data class CredentialResponse(val deviceId: String, val credential: String)

@Serializable
data class InvitationResponse(val invitation: String, val expiresAt: String)

@Serializable
data class HealthResponse(val status: String)

@Serializable
data class ErrorResponse(val error: String)

@Serializable
internal data class RelayState(
    val version: Int = 1,
    val setup: SetupState,
    val devices: Map<String, DeviceRecord> = emptyMap(),
    val invitations: Map<String, InvitationRecord> = emptyMap(),
)

@Serializable
internal data class SetupState(
    val tokenHash: String,
    val expiresAtEpochSeconds: Long,
    val consumed: Boolean = false,
)

@Serializable
internal data class DeviceRecord(
    val deviceId: String,
    val workspaceId: String,
    val deviceType: DeviceType,
    val credentialHash: String,
    val peerDeviceId: String? = null,
    val revoked: Boolean = false,
)

@Serializable
internal data class InvitationRecord(
    val tokenHash: String,
    val workspaceId: String,
    val inviterDeviceId: String,
    val deviceType: DeviceType,
    val expiresAtEpochSeconds: Long,
    val consumed: Boolean = false,
)
