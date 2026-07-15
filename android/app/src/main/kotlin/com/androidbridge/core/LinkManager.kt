package com.androidbridge.core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.net.nsd.NsdManager
import android.os.Build
import android.net.nsd.NsdServiceInfo
import android.os.Environment
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Base64
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import com.androidbridge.MainActivity
import com.androidbridge.android.CallStateReceiver
import com.androidbridge.android.ClipboardCopyReceiver
import com.androidbridge.android.MeetingRecorderService
import com.androidbridge.android.RemoteControlService
import com.androidbridge.android.ScreenShareService
import com.androidbridge.feature.Mappers
import com.androidbridge.protocol.Message
import com.androidbridge.protocol.MessageTypes
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import javax.net.ssl.SSLServerSocket
import java.util.UUID

/** A peer discovered on the LAN (mDNS/NSD), with its advertised fingerprint. */
data class NearbyPeer(val name: String, val host: String, val port: Int, val fingerprint: String)
data class ReceivedFile(val name: String, val uri: Uri)

/**
 * The runtime device link (U3): discovers the Mac over NSD, connects with pinned TLS, and routes
 * protocol messages (clipboard, notifications, SMS, calls, file transfer, screen frames).
 */
class LinkManager(
    private val context: Context,
    private val deviceName: String,
    private val identity: CertFactory.Identity,
    private val store: SecureStore,
    private val scope: CoroutineScope,
) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val router = MessageRouter()
    private val outbox = Channel<Message>(Channel.UNLIMITED)
    private val sendLock = Any()
    private val brainFolder = SecondBrainFolder(context)

    private val _status = MutableStateFlow(ConnectionState.DISCONNECTED)
    val status: StateFlow<ConnectionState> = _status.asStateFlow()
    private val _nearby = MutableStateFlow<List<NearbyPeer>>(emptyList())
    val nearby: StateFlow<List<NearbyPeer>> = _nearby.asStateFlow()
    private val _pairedFingerprints = MutableStateFlow(loadPaired())
    val pairedFingerprints: StateFlow<Set<String>> = _pairedFingerprints.asStateFlow()
    private val _lastClipboard = MutableStateFlow<String?>(null)
    val lastClipboard: StateFlow<String?> = _lastClipboard.asStateFlow()
    private val _events = MutableStateFlow<List<String>>(emptyList())
    val events: StateFlow<List<String>> = _events.asStateFlow()
    private val _peerScreen = MutableStateFlow<Bitmap?>(null)
    val peerScreen: StateFlow<Bitmap?> = _peerScreen.asStateFlow()
    private val _receivedFiles = MutableStateFlow<List<ReceivedFile>>(emptyList())
    val receivedFiles: StateFlow<List<ReceivedFile>> = _receivedFiles.asStateFlow()
    private val _brainNodes = MutableStateFlow<List<SecondBrainNode>>(emptyList())
    val brainNodes: StateFlow<List<SecondBrainNode>> = _brainNodes.asStateFlow()
    private val _selectedBrainPath = MutableStateFlow("")
    val selectedBrainPath: StateFlow<String> = _selectedBrainPath.asStateFlow()
    private val _selectedBrainContent = MutableStateFlow("")
    val selectedBrainContent: StateFlow<String> = _selectedBrainContent.asStateFlow()
    private val _brainSearchResults = MutableStateFlow<List<SecondBrainNode>>(emptyList())
    val brainSearchResults: StateFlow<List<SecondBrainNode>> = _brainSearchResults.asStateFlow()
    private val _brainStatus = MutableStateFlow("")
    val brainStatus: StateFlow<String> = _brainStatus.asStateFlow()
    private val _brainHasFolder = MutableStateFlow(brainFolder.hasFolder())
    val brainHasFolder: StateFlow<Boolean> = _brainHasFolder.asStateFlow()
    private val _brainFolderName = MutableStateFlow(brainFolder.folderName())
    val brainFolderName: StateFlow<String> = _brainFolderName.asStateFlow()

    val fingerprint: String get() = identity.fingerprint
    val connected: Boolean get() = session != null

    private var server: SSLServerSocket? = null
    @Volatile private var session: TlsLink.Session? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var incoming: IncomingFile? = null

    private class IncomingFile(val name: String, val size: Int, val buffer: ByteArrayOutputStream = ByteArrayOutputStream())

    private fun field(msg: Message, key: String): String = msg.payload[key]?.jsonPrimitive?.content ?: ""

    private fun pushEvent(text: String) { _events.value = (listOf(text) + _events.value).take(12) }

    private var notifId = 3000
    /** Post a native Android notification for an inbound peer event (requires POST_NOTIFICATIONS). */
    private fun notify(title: String, text: String, intent: PendingIntent? = null) {
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.createNotificationChannel(NotificationChannel("peer_events", "Peer events", NotificationManager.IMPORTANCE_HIGH))
        val builder = Notification.Builder(context, "peer_events")
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setAutoCancel(true)
        if (intent != null) {
            builder.setContentIntent(intent)
            builder.addAction(android.R.drawable.ic_menu_view, "Open", intent)
        }
        mgr.notify(notifId++, builder.build())
    }

    private fun fileOpenIntent(uri: Uri): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "*/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return PendingIntent.getActivity(context, notifId, Intent.createChooser(intent, "Open file"), PendingIntent.FLAG_IMMUTABLE)
    }

    private fun clipboardCopyIntent(text: String): PendingIntent {
        val intent = Intent(context, ClipboardCopyReceiver::class.java).apply {
            action = ClipboardCopyReceiver.ACTION_COPY_CLIPBOARD
            putExtra(ClipboardCopyReceiver.EXTRA_TEXT, text)
        }
        return PendingIntent.getBroadcast(context, notifId, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    init {
        router.register(MessageTypes.CLIP_UPDATE) { m ->
            val text = field(m, "text")
            _lastClipboard.value = text
            pushEvent("📋 Clipboard: $text")
        }
        router.register(MessageTypes.NOTIF_POSTED) { m ->
            val t = field(m, "title"); val x = field(m, "text")
            pushEvent("🔔 $t: $x"); notify(t, x)
        }
        router.register(MessageTypes.SMS_RECEIVED) { m ->
            val a = field(m, "address"); val b = field(m, "body")
            pushEvent("✉️ SMS $a: $b"); notify("SMS from $a", b)
        }
        router.register(MessageTypes.CALL_INCOMING) { m ->
            val who = field(m, "contactName").ifEmpty { field(m, "number") }
            pushEvent("📞 Incoming call: $who"); notify("Incoming call", who)
        }
        router.register(MessageTypes.CALL_ACTION) { m -> handleCallAction(field(m, "action"), field(m, "number")) }
        router.register(MessageTypes.SCREEN_REQUEST) { requestScreenShare() }
        router.register(MessageTypes.INPUT_TAP) { m -> remoteTap(field(m, "x").toFloat(), field(m, "y").toFloat(), field(m, "w").toFloat(), field(m, "h").toFloat()) }
        router.register(MessageTypes.INPUT_SWIPE) { m -> remoteSwipe(field(m, "x1").toFloat(), field(m, "y1").toFloat(), field(m, "x2").toFloat(), field(m, "y2").toFloat(), field(m, "w").toFloat(), field(m, "h").toFloat()) }
        router.register(MessageTypes.SCREEN_START) { pushEvent("🖥️ Screen mirror requested") }
        router.register(MessageTypes.SCREEN_FRAME) { m ->
            Log.i("AndroidBridge", "rx screen.frame payload=${field(m, "data").length}")
            val bytes = Base64.decode(field(m, "data"), Base64.NO_WRAP)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let {
                if (_peerScreen.value == null) {
                    context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    pushEvent("🖥️ Mac screen started ${it.width}×${it.height}")
                }
                _peerScreen.value = it
            }
        }
        router.register(MessageTypes.FILE_OFFER) { m ->
            incoming = IncomingFile(field(m, "name"), field(m, "size").toIntOrNull() ?: 0)
            pushEvent("📎 Receiving ${incoming?.name}…")
        }
        router.register(MessageTypes.FILE_CHUNK) { m ->
            val asm = incoming ?: return@register
            asm.buffer.write(Base64.decode(field(m, "data"), Base64.NO_WRAP))
            if (field(m, "last") == "true") {
                val uri = saveIncomingFile(asm.name, asm.buffer.toByteArray())
                _receivedFiles.value = (listOf(ReceivedFile(asm.name, uri)) + _receivedFiles.value).take(20)
                pushEvent("📎 Saved ${asm.name} (${asm.buffer.size()} B)")
                notify("File received", "Tap to open ${asm.name}", fileOpenIntent(uri))
                incoming = null
                android.util.Log.i("AndroidBridge", "file saved: $uri")
            }
        }
        router.register(MessageTypes.LINK_HELLO) { LinkLogger.info("peer_hello") }
        router.register(MessageTypes.MEETING_START) { m -> startMeetingFromMac(field(m, "meetingId"), field(m, "title")) }
        router.register(MessageTypes.MEETING_STOP) { stopMeetingFromMac() }
        router.register(MessageTypes.MEETING_AUDIO_CHUNK_RECEIVED) { m ->
            val name = "meeting-${field(m, "meetingId")}-${field(m, "sequence")}.m4a"
            File(context.filesDir, name).delete()
            pushEvent("🎙️ Meeting chunk confirmed ${field(m, "sequence")}")
        }
        router.register(MessageTypes.MEETING_PHOTO_RECEIVED) { m ->
            File(context.filesDir, "meeting-${field(m, "photoId")}.jpg").delete()
            pushEvent("📷 Meeting photo confirmed")
        }
        router.register(MessageTypes.MEETING_PROCESSING_STATUS) { m -> pushEvent("📝 Meeting ${field(m, "state")}") }
        router.register(MessageTypes.MEETING_NOTES_READY) { m -> pushEvent("📝 Notes ready on Mac") }
        router.register(MessageTypes.LINK_HEARTBEAT) { }
    }

    fun start() {
        scope.launch(Dispatchers.IO) { senderLoop() }
        val srv = TlsLink.openServer(identity, 0)
        server = srv
        scope.launch(Dispatchers.IO) { acceptLoop(srv) }
        registerService(srv.localPort)
        startBrowsing()
        _status.value = ConnectionState.DISCOVERING
        if (brainFolder.hasFolder()) refreshSecondBrain()
    }

    /** Single serialized writer — all outbound messages go through one coroutine so socket writes
     *  never interleave (concurrent writes would corrupt the stream). */
    private suspend fun senderLoop() {
        for (msg in outbox) {
            val s = session ?: continue
            runCatching { synchronized(sendLock) { s.send(msg) } }.onFailure {
                // A dead peer socket must not linger as a zombie session — close it so the
                // receive loop exits, session clears, and a fresh connection can be adopted.
                LinkLogger.warn("send_failed", mapOf("err" to (it.message ?: "?")))
                runCatching { s.close() }
            }
        }
    }

    private fun send(message: Message) {
        Log.i("AndroidBridge", "tx ${message.type}")
        outbox.trySend(message)
    }

    private fun sendDirect(message: Message) {
        val s = session ?: return
        synchronized(sendLock) { s.send(message) }
    }

    private suspend fun acceptLoop(srv: SSLServerSocket) {
        while (scope.isActive && !srv.isClosed) {
            val accepted = runCatching { TlsLink.accept(srv) }.getOrNull() ?: continue
            adopt(accepted)
        }
    }

    fun pair(peer: NearbyPeer) {
        _pairedFingerprints.value = _pairedFingerprints.value + peer.fingerprint
        savePaired(_pairedFingerprints.value)
    }

    private fun adopt(s: TlsLink.Session) {
        if (session != null) { runCatching { s.close() }; return }
        session = s
        _status.value = ConnectionState.CONNECTED
        scope.launch(Dispatchers.IO) { receiveLoop(s) }
        scope.launch(Dispatchers.IO) { heartbeatLoop(s) }
        syncOngoingCall()
    }

    /** A call that started before the link connected never produced a state broadcast
     *  the Mac could see — report the current call now so the in-call panel appears. */
    private fun syncOngoingCall() {
        val telephony = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        when (runCatching { telephony.callState }.getOrNull()) {
            TelephonyManager.CALL_STATE_OFFHOOK -> sendCallState("active", CallStateReceiver.lastNumber, CallStateReceiver.lastName)
            TelephonyManager.CALL_STATE_RINGING -> sendIncomingCall(CallStateReceiver.lastNumber, CallStateReceiver.lastName)
            else -> {}
        }
    }

    private fun receiveLoop(s: TlsLink.Session) {
        while (scope.isActive) {
            val msg = runCatching { s.receive() }.getOrNull() ?: break
            router.route(msg)
        }
        if (session === s) {
            session = null
            _peerScreen.value = null
            _status.value = ConnectionState.DISCONNECTED
        }
        runCatching { s.close() }
    }

    private suspend fun heartbeatLoop(s: TlsLink.Session) {
        while (scope.isActive && session === s) {
            delay(5000)
            if (session === s) send(Message(id = UUID.randomUUID().toString(), type = MessageTypes.LINK_HEARTBEAT))
        }
    }

    private fun requestScreenShare() {
        if (ScreenShareService.isRunning) {
            pushEvent("🖥️ Screen share already running")
            return
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_REQUEST_SCREEN_SHARE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        pushEvent("🖥️ Mac requested screen share")
    }

    private fun screenScale(w: Float, h: Float): Pair<Float, Float> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        return metrics.widthPixels / w to metrics.heightPixels / h
    }

    private fun remoteTap(x: Float, y: Float, w: Float, h: Float) {
        val svc = RemoteControlService.instance ?: run { notify("Mac control disabled", "Open Android Bridge and tap Enable Mac control"); return }
        val (sx, sy) = screenScale(w, h)
        svc.tap(x * sx, y * sy)
    }

    private fun remoteSwipe(x1: Float, y1: Float, x2: Float, y2: Float, w: Float, h: Float) {
        val svc = RemoteControlService.instance ?: run { notify("Mac control disabled", "Open Android Bridge and tap Enable Mac control"); return }
        val (sx, sy) = screenScale(w, h)
        svc.swipe(x1 * sx, y1 * sy, x2 * sx, y2 * sy)
    }

    /** Forward a real ringing call to the Mac so it can answer/decline remotely. */
    fun sendIncomingCall(number: String, contactName: String? = null) {
        send(Mappers.incomingCall(number, contactName))
        pushEvent("📞 Ringing → Mac: $number")
    }

    /** Report a call lifecycle transition to the Mac: "active" (off-hook) or "ended" (idle). */
    fun sendCallState(state: String, number: String, contactName: String? = null) {
        send(Mappers.callState(state, number, contactName))
        pushEvent("📞 Call $state → Mac${if (number.isBlank()) "" else ": $number"}")
    }

    /** Execute a call command from the Mac: answer/decline the current call or dial a number. */
    @Suppress("DEPRECATION") // acceptRingingCall/endCall: the only non-default-dialer APIs for this
    private fun handleCallAction(action: String, number: String) {
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val result = runCatching {
            when (action) {
                "answer", "accept" -> telecom.acceptRingingCall()
                "decline", "hangup" -> telecom.endCall()
                "dial" -> dialFromMac(telecom, number)
                else -> return
            }
        }
        result.onFailure { LinkLogger.warn("call_action_failed", mapOf("action" to action, "err" to (it.message ?: "?"))) }
        pushEvent(if (result.isSuccess) "📞 Mac: $action $number".trim() else "📞 $action failed: ${result.exceptionOrNull()?.message}")
    }

    private fun dialFromMac(telecom: TelecomManager, number: String) {
        if (number.isBlank()) return
        if (Build.VERSION.SDK_INT >= 23) {
            telecom.placeCall(Uri.parse("tel:$number"), null)
            return
        }
        context.startActivity(Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun startMeetingFromMac(meetingId: String, title: String) {
        val intent = Intent(context, MeetingRecorderService::class.java).apply {
            action = MeetingRecorderService.ACTION_START
            putExtra(MeetingRecorderService.EXTRA_MEETING_ID, meetingId)
            putExtra(MeetingRecorderService.EXTRA_TITLE, title)
        }
        androidx.core.content.ContextCompat.startForegroundService(context, intent)
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        pushEvent("🎙️ Meeting started from Mac")
    }

    private fun stopMeetingFromMac() {
        context.startService(Intent(context, MeetingRecorderService::class.java).apply { action = MeetingRecorderService.ACTION_STOP })
        pushEvent("🎙️ Meeting stopped from Mac")
    }

    // Feature senders
    fun sendClipboard(text: String) = send(Mappers.clipboard(text))

    fun setBrainFolder(uri: Uri) {
        brainFolder.setFolder(uri)
        _brainHasFolder.value = true
        _brainFolderName.value = brainFolder.folderName()
        refreshSecondBrain()
    }

    fun refreshSecondBrain() {
        scope.launch(Dispatchers.IO) {
            val nodes = brainFolder.nodes()
            _brainNodes.value = nodes
            _brainStatus.value = "${nodes.count { !it.isDirectory }} notes in ${brainFolder.folderName()}"
        }
    }

    fun selectSecondBrainNode(path: String) {
        _selectedBrainPath.value = path
        scope.launch(Dispatchers.IO) { _selectedBrainContent.value = brainFolder.content(path) }
    }

    fun saveSecondBrainNode(path: String, content: String) {
        scope.launch(Dispatchers.IO) {
            brainFolder.save(path, content)
            _brainNodes.value = brainFolder.nodes()
            if (_selectedBrainPath.value == path) _selectedBrainContent.value = content
            _brainStatus.value = "Saved ${path.substringAfterLast('/')}"
        }
    }

    fun deleteSecondBrainNode(path: String) {
        if (_selectedBrainPath.value == path) { _selectedBrainPath.value = ""; _selectedBrainContent.value = "" }
        scope.launch(Dispatchers.IO) {
            brainFolder.delete(path)
            _brainNodes.value = brainFolder.nodes()
            _brainStatus.value = "Deleted ${path.substringAfterLast('/')}"
        }
    }

    fun searchSecondBrain(query: String) {
        scope.launch(Dispatchers.IO) { _brainSearchResults.value = brainFolder.search(query) }
    }

    fun sendTestNotification() = send(Mappers.notification("com.demo.app", "Test notification", "Hello from $deviceName", 0))
    fun sendTestSms() = send(Mappers.smsReceived(1, "+1 555 0100", "Test SMS from $deviceName", 0))
    fun sendSmsReceived(address: String, body: String, receivedAt: Long) = send(Mappers.smsReceived(0, address, body, receivedAt))
    fun sendTestCall() = send(Mappers.incomingCall("+1 555 0199", "Test Caller"))

    fun sendMacTap(x: Float, y: Float, w: Float, h: Float) = send(Message(UUID.randomUUID().toString(), MessageTypes.INPUT_TAP, payload = buildJsonObject {
        put("x", x.toString()); put("y", y.toString()); put("w", w.toString()); put("h", h.toString())
    }))

    fun sendMacSwipe(x1: Float, y1: Float, x2: Float, y2: Float, w: Float, h: Float) = send(Message(UUID.randomUUID().toString(), MessageTypes.INPUT_SWIPE, payload = buildJsonObject {
        put("x1", x1.toString()); put("y1", y1.toString()); put("x2", x2.toString()); put("y2", y2.toString()); put("w", w.toString()); put("h", h.toString())
    }))

    fun sendScreenFrame(jpegBase64: String, width: Int, height: Int) = send(
        Message(id = UUID.randomUUID().toString(), type = MessageTypes.SCREEN_FRAME, payload = buildJsonObject {
            put("data", jpegBase64); put("w", width); put("h", height)
        })
    )

    fun sendMeetingStart(meetingId: String, title: String?) = send(com.androidbridge.feature.Mappers.meetingStart(meetingId, title, System.currentTimeMillis()))
    fun sendMeetingStop(meetingId: String) = send(com.androidbridge.feature.Mappers.meetingStop(meetingId, System.currentTimeMillis()))

    fun sendMeetingAudioChunk(meetingId: String, sequence: Int, startedAtMs: Long, endedAtMs: Long, file: File) {
        val bytes = file.readBytes()
        send(com.androidbridge.feature.Mappers.meetingAudioChunk(meetingId, sequence, startedAtMs, endedAtMs, sha256(bytes), file.name, Base64.encodeToString(bytes, Base64.NO_WRAP)))
        pushEvent("🎙️ Sent meeting chunk $sequence")
    }

    fun sendMeetingPhoto(meetingId: String, photoId: String, capturedAtMs: Long, file: File) {
        val bytes = file.readBytes()
        send(com.androidbridge.feature.Mappers.meetingPhoto(meetingId, photoId, capturedAtMs, sha256(bytes), file.name, Base64.encodeToString(bytes, Base64.NO_WRAP)))
        pushEvent("📷 Sent meeting photo")
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    /** Send a file both ways, chunked. Streams input so large videos are not loaded into RAM. */
    fun sendFile(name: String, bytes: ByteArray) = sendFileStream(name, bytes.size.toLong(), bytes.inputStream())

    fun sendFileStream(name: String, size: Long, input: InputStream) {
        sendDirect(Message(id = UUID.randomUUID().toString(), type = MessageTypes.FILE_OFFER, payload = buildJsonObject {
            put("name", name); put("size", size)
        }))
        input.use { stream ->
            val buffer = ByteArray(48 * 1024)
            var seq = 0
            var sent = 0L
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) break
                sent += read
                val last = size >= 0 && sent >= size
                val slice = if (read == buffer.size) buffer else buffer.copyOf(read)
                sendDirect(Message(id = UUID.randomUUID().toString(), type = MessageTypes.FILE_CHUNK, payload = buildJsonObject {
                    put("seq", seq); put("data", Base64.encodeToString(slice, Base64.NO_WRAP)); put("last", last.toString())
                }))
                seq++
            }
            if (size < 0) {
                sendDirect(Message(id = UUID.randomUUID().toString(), type = MessageTypes.FILE_CHUNK, payload = buildJsonObject {
                    put("seq", seq); put("data", ""); put("last", "true")
                }))
            }
        }
        pushEvent("📎 Sent $name")
    }

    /** Save to the public Downloads folder (visible in the Files app), via MediaStore. */
    private fun saveIncomingFile(name: String, bytes: ByteArray): Uri {
        return try {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return fallbackSave(name, bytes)
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
            values.clear(); values.put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            uri
        } catch (e: Exception) {
            fallbackSave(name, bytes)
        }
    }

    private fun fallbackSave(name: String, bytes: ByteArray): Uri {
        val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir
        val file = File(dir, name)
        file.writeBytes(bytes)
        return Uri.fromFile(file)
    }

    fun stop() {
        runCatching { session?.close() }
        runCatching { server?.close() }
        registrationListener?.let { runCatching { nsd.unregisterService(it) } }
        discoveryListener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
    }

    private fun registerService(port: Int) {
        val info = NsdServiceInfo().apply {
            serviceName = "AndroidBridge-$deviceName"
            serviceType = SERVICE_TYPE
            setPort(port)
            setAttribute("fp", identity.fingerprint)
            setAttribute("name", deviceName)
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) { LinkLogger.info("nsd_registered") }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        registrationListener = listener
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun startBrowsing() {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceName == "AndroidBridge-$deviceName") return
                nsd.resolveService(service, resolveListener())
            }
            override fun onServiceLost(service: NsdServiceInfo) {
                // Remove any nearby entry matching this instance name.
                _nearby.value = _nearby.value.filter { "AndroidBridge-${it.name}" != service.serviceName }
            }
        }
        discoveryListener = listener
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun resolveListener() = object : NsdManager.ResolveListener {
        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
            val host = serviceInfo.host?.hostAddress ?: return
            val fp = serviceInfo.attributes["fp"]?.let { String(it) } ?: return
            val name = serviceInfo.attributes["name"]?.let { String(it) } ?: serviceInfo.serviceName
            if (fp == identity.fingerprint) return
            val peer = NearbyPeer(name, host, serviceInfo.port, fp)
            // Dedupe by fingerprint (keep latest host/port).
            _nearby.value = _nearby.value.filter { it.fingerprint != fp } + peer
        }
    }

    private fun loadPaired(): Set<String> =
        store.get(KEY_PAIRED)?.split("\n")?.filter { it.isNotBlank() }?.toSet() ?: emptySet()

    private fun savePaired(set: Set<String>) { store.put(KEY_PAIRED, set.joinToString("\n")) }

    companion object {
        const val SERVICE_TYPE = "_androidbridge._tcp."
        private const val KEY_PAIRED = "paired.fingerprints"
    }
}
