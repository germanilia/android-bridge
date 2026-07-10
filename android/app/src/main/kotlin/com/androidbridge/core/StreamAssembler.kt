package com.androidbridge.core

import com.androidbridge.protocol.DEFAULT_CHUNK_BYTES
import com.androidbridge.protocol.FLAG_END_OF_STREAM
import com.androidbridge.protocol.Frame
import com.androidbridge.protocol.FrameHeader

/**
 * Splits a payload into ordered binary frames (file/screen bulk) and reassembles them, enforcing
 * the ordering invariant from PROTOCOL.md §5 (sequence gaps/dupes fault the stream — fail-closed).
 * Pure logic — JVM-testable; the round-trip is a PBT target (PBT-03).
 */
object StreamChunker {

    /** Chunk [data] into frames of at most [chunkSize] bytes, marking the last with END_OF_STREAM. */
    fun chunk(streamId: Long, data: ByteArray, chunkSize: Int = DEFAULT_CHUNK_BYTES): List<Frame> {
        require(chunkSize > 0)
        if (data.isEmpty()) {
            return listOf(Frame(FrameHeader(streamId, 0, 0, FLAG_END_OF_STREAM), ByteArray(0)))
        }
        val frames = ArrayList<Frame>()
        var seq = 0L
        var offset = 0
        while (offset < data.size) {
            val end = minOf(offset + chunkSize, data.size)
            val slice = data.copyOfRange(offset, end)
            val isLast = end == data.size
            val flags = if (isLast) FLAG_END_OF_STREAM else 0
            frames.add(Frame(FrameHeader(streamId, seq, slice.size, flags), slice))
            seq++
            offset = end
        }
        return frames
    }
}

/** Reassembles frames for a single stream, enforcing ordering. */
class StreamReassembler(private val streamId: Long) {
    private val buffer = java.io.ByteArrayOutputStream()
    private var expectedSeq = 0L
    var complete: Boolean = false
        private set

    /** Accept the next frame. Returns false (and faults) on wrong stream, gap, or dup. */
    fun accept(frame: Frame): Boolean {
        if (complete) return false
        if (frame.header.streamId != streamId) return fault("wrong_stream")
        if (frame.header.sequence != expectedSeq) return fault("sequence_gap")
        buffer.write(frame.payload)
        expectedSeq++
        if (frame.header.isEndOfStream) complete = true
        return true
    }

    fun result(): ByteArray = buffer.toByteArray()

    private fun fault(reason: String): Boolean {
        LinkLogger.securityEvent("stream_faulted", mapOf("streamId" to streamId.toString(), "reason" to reason))
        return false
    }
}
