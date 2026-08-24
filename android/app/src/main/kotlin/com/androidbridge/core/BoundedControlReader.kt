package com.androidbridge.core

import com.androidbridge.protocol.MAX_CONTROL_BYTES
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import com.androidbridge.protocol.ProtocolErrorCode
import com.androidbridge.protocol.ProtocolException
import java.io.DataInputStream

/** Reads one control frame and rejects its declared size before allocating the body. */
object BoundedControlReader {
    fun read(input: DataInputStream): Message {
        val header = ByteArray(4)
        input.readFully(header)
        val length = ((header[0].toLong() and 0xFF) shl 24) or
            ((header[1].toLong() and 0xFF) shl 16) or
            ((header[2].toLong() and 0xFF) shl 8) or
            (header[3].toLong() and 0xFF)
        if (length > MAX_CONTROL_BYTES) throw ProtocolException(ProtocolErrorCode.OVERSIZE)
        val body = ByteArray(length.toInt())
        input.readFully(body)
        return MessageCodec.decode(header + body)
    }
}
