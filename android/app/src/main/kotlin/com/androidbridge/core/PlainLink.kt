package com.androidbridge.core

import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageCodec
import java.io.DataInputStream
import java.net.ServerSocket
import java.net.Socket

/**
 * ⚠️ DEMO-ONLY transport: plaintext TCP carrying length-prefixed protocol messages, used for the
 * walking-skeleton demo so phone↔Mac works without the self-signed-cert → SecIdentity → Network.framework
 * mutual-TLS integration. NOT for production — the real link is [TlsLink] (mutual TLS, cert pinning),
 * which is implemented and integration-tested; wiring it across Android↔Apple is the remaining work.
 */
object PlainLink {
    class Session(private val socket: Socket) {
        private val input = DataInputStream(socket.inputStream)
        private val output = socket.outputStream

        fun send(message: Message) {
            output.write(MessageCodec.encode(message))
            output.flush()
        }

        fun receive(): Message {
            val header = ByteArray(4)
            input.readFully(header)
            val len = ((header[0].toInt() and 0xFF) shl 24) or ((header[1].toInt() and 0xFF) shl 16) or
                ((header[2].toInt() and 0xFF) shl 8) or (header[3].toInt() and 0xFF)
            val body = ByteArray(len)
            input.readFully(body)
            return MessageCodec.decode(header + body)
        }

        fun close() = socket.close()
    }

    fun openServer(port: Int = 0): ServerSocket = ServerSocket(port)
    fun accept(server: ServerSocket): Session = Session(server.accept())
    fun connect(host: String, port: Int): Session = Session(Socket(host, port))
}
