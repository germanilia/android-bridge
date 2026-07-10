package com.androidbridge.protocol

import kotlinx.serialization.json.Json

internal fun writeU32BE(buf: ByteArray, off: Int, v: Long) {
    buf[off] = ((v ushr 24) and 0xFF).toByte()
    buf[off + 1] = ((v ushr 16) and 0xFF).toByte()
    buf[off + 2] = ((v ushr 8) and 0xFF).toByte()
    buf[off + 3] = (v and 0xFF).toByte()
}

internal fun readU32BE(buf: ByteArray, off: Int): Long =
    ((buf[off].toLong() and 0xFF) shl 24) or
        ((buf[off + 1].toLong() and 0xFF) shl 16) or
        ((buf[off + 2].toLong() and 0xFF) shl 8) or
        (buf[off + 3].toLong() and 0xFF)

/** Validate an inbound message against the registry + envelope rules — PROTOCOL.md §4. */
fun validate(message: Message): ValidationResult {
    if (message.protocolVersion != PROTOCOL_VERSION) return ValidationResult.fail(ProtocolErrorCode.VERSION_MISMATCH)
    if (message.type !in MessageTypes.known) return ValidationResult.fail(ProtocolErrorCode.UNKNOWN_TYPE)
    if (message.id.isEmpty()) return ValidationResult.fail(ProtocolErrorCode.SCHEMA_MISMATCH)
    return ValidationResult.OK
}

/** Length-prefixed JSON control codec — PROTOCOL.md §3–§4. */
object MessageCodec {
    val json: Json = Json {
        encodeDefaults = false
        ignoreUnknownKeys = false
        isLenient = false
    }

    /** Encode a control message to `[4-byte BE length][UTF-8 JSON]`. */
    fun encode(message: Message): ByteArray {
        val body = json.encodeToString(Message.serializer(), message).encodeToByteArray()
        if (body.size > MAX_CONTROL_BYTES) throw ProtocolException(ProtocolErrorCode.OVERSIZE)
        val out = ByteArray(4 + body.size)
        writeU32BE(out, 0, body.size.toLong())
        body.copyInto(out, 4)
        return out
    }

    /** Decode exactly one control message (trailing bytes are ignored). */
    fun decode(bytes: ByteArray): Message = decodeNext(bytes, 0).first

    /** Decode the message at [offset], returning it and the offset just past it. */
    fun decodeNext(bytes: ByteArray, offset: Int): Pair<Message, Int> {
        if (bytes.size - offset < 4) throw ProtocolException(ProtocolErrorCode.MALFORMED_LENGTH)
        val len = readU32BE(bytes, offset)
        if (len > MAX_CONTROL_BYTES) throw ProtocolException(ProtocolErrorCode.OVERSIZE)
        val start = offset + 4
        if (bytes.size - start < len) throw ProtocolException(ProtocolErrorCode.MALFORMED_LENGTH)
        val jsonStr = String(bytes, start, len.toInt(), Charsets.UTF_8)
        val message = try {
            json.decodeFromString(Message.serializer(), jsonStr)
        } catch (e: Exception) {
            throw ProtocolException(ProtocolErrorCode.MALFORMED_JSON)
        }
        val vr = validate(message)
        if (!vr.valid) throw ProtocolException(vr.code!!)
        return message to (start + len.toInt())
    }

    /** Decode a sequence of self-delimiting control messages. */
    fun decodeStream(bytes: ByteArray): List<Message> {
        val out = ArrayList<Message>()
        var off = 0
        while (off < bytes.size) {
            val (m, next) = decodeNext(bytes, off)
            out.add(m)
            off = next
        }
        return out
    }
}

/** Binary frame codec — PROTOCOL.md §5. */
object FrameCodec {
    fun encodeFrame(header: FrameHeader, payload: ByteArray): ByteArray {
        if (payload.size != header.length) throw ProtocolException(ProtocolErrorCode.BAD_FRAME_HEADER)
        val out = ByteArray(FRAME_HEADER_BYTES + payload.size)
        writeU32BE(out, 0, header.streamId)
        writeU32BE(out, 4, header.sequence)
        writeU32BE(out, 8, header.length.toLong())
        out[12] = (header.flags and 0xFF).toByte()
        payload.copyInto(out, FRAME_HEADER_BYTES)
        return out
    }

    fun decodeFrame(bytes: ByteArray): Frame {
        if (bytes.size < FRAME_HEADER_BYTES) throw ProtocolException(ProtocolErrorCode.BAD_FRAME_HEADER)
        val streamId = readU32BE(bytes, 0)
        val sequence = readU32BE(bytes, 4)
        val length = readU32BE(bytes, 8)
        val flags = bytes[12].toInt() and 0xFF
        if (bytes.size - FRAME_HEADER_BYTES < length) throw ProtocolException(ProtocolErrorCode.BAD_FRAME_HEADER)
        val payload = bytes.copyOfRange(FRAME_HEADER_BYTES, FRAME_HEADER_BYTES + length.toInt())
        return Frame(FrameHeader(streamId, sequence, length.toInt(), flags), payload)
    }
}
