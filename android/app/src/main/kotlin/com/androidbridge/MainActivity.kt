package com.androidbridge

import android.content.Context
import android.content.Intent
import android.content.ClipboardManager
import android.graphics.Bitmap
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.androidbridge.android.LinkForegroundService
import com.androidbridge.android.MeetingRecorderService
import com.androidbridge.android.ScreenShareService
import com.androidbridge.core.ConnectionState
import com.androidbridge.core.LinkHolder
import com.androidbridge.core.LinkManager
import com.androidbridge.core.NearbyPeer
import com.androidbridge.core.ReceivedFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

private val BrandScheme = darkColorScheme(
    primary = Color(0xFF818CF8), onPrimary = Color(0xFF0B1020),
    primaryContainer = Color(0xFF312E81), onPrimaryContainer = Color(0xFFE0E7FF),
    background = Color(0xFF0B1020), onBackground = Color(0xFFE2E8F0),
    surface = Color(0xFF141B2E), onSurface = Color(0xFFE2E8F0),
    surfaceVariant = Color(0xFF1E263B), onSurfaceVariant = Color(0xFF94A3B8),
    outline = Color(0xFF334155),
)
private val Emerald = Color(0xFF10B981)
private val Amber = Color(0xFFF59E0B)
private val Slate = Color(0xFF64748B)

class MainActivity : ComponentActivity() {
    private lateinit var link: LinkManager
    private val sharing = mutableStateOf(false)
    private val meetingRecording = mutableStateOf(false)
    private val meetingPaused = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val wanted = buildList {
            if (Build.VERSION.SDK_INT >= 33) add(android.Manifest.permission.POST_NOTIFICATIONS)
            // Calls from the Mac: see who's calling, answer/hang up, and dial out.
            add(android.Manifest.permission.READ_PHONE_STATE)
            add(android.Manifest.permission.READ_CALL_LOG)
            add(android.Manifest.permission.READ_CONTACTS)
            add(android.Manifest.permission.RECEIVE_SMS)
            add(android.Manifest.permission.READ_SMS)
            add(android.Manifest.permission.CALL_PHONE)
            add(android.Manifest.permission.ANSWER_PHONE_CALLS)
            add(android.Manifest.permission.RECORD_AUDIO)
            add(android.Manifest.permission.CAMERA)
        }
        val missing = wanted.filter { checkSelfPermission(it) != android.content.pm.PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 100)
        ContextCompat.startForegroundService(this, Intent(this, LinkForegroundService::class.java))
        link = LinkHolder.ensure(applicationContext)
        handleShare(intent)
        if (intent.action == ACTION_REQUEST_SCREEN_SHARE) startScreenShare()
        lifecycleScope.launch { link.status.collect { if (it == ConnectionState.CONNECTED) flushPending() } }
        setContent {
            MaterialTheme(colorScheme = BrandScheme) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    HomeScreen(link, ::currentClipboard, sharing.value, meetingRecording.value, meetingPaused.value, ::startScreenShare, ::stopScreenShare, ::startMeeting, ::pauseMeeting, ::resumeMeeting, ::stopMeeting, ::takeMeetingPhoto, ::pickFile, ::openReceivedFile, ::openAccessibilitySettings, ::onClipReceived)
                }
            }
        }
    }

    private val captureLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val data = result.data
        if (result.resultCode == RESULT_OK && data != null) {
            val intent = Intent(this, ScreenShareService::class.java).apply {
                putExtra(ScreenShareService.EXTRA_CODE, result.resultCode)
                putExtra(ScreenShareService.EXTRA_DATA, data)
            }
            ContextCompat.startForegroundService(this, intent)
            sharing.value = true
        }
    }

    private val filePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri ?: return@registerForActivityResult
        lifecycleScope.launch(Dispatchers.IO) {
            val input = contentResolver.openInputStream(uri) ?: return@launch
            link.sendFileStream(queryName(uri), querySize(uri), input)
        }
    }

    private val photoLauncher = registerForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap: Bitmap? ->
        val meetingId = MeetingRecorderService.activeMeetingId
        if (bitmap == null || meetingId == null) return@registerForActivityResult
        lifecycleScope.launch(Dispatchers.IO) {
            val photoId = UUID.randomUUID().toString()
            val file = File(filesDir, "meeting-$photoId.jpg")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
            link.sendMeetingPhoto(meetingId, photoId, System.currentTimeMillis(), file)
        }
    }

    private fun pickFile() = filePicker.launch("*/*")
    private fun startMeeting() {
        meetingRecording.value = true
        meetingPaused.value = false
        ContextCompat.startForegroundService(this, Intent(this, MeetingRecorderService::class.java).apply { action = MeetingRecorderService.ACTION_START })
    }
    private fun pauseMeeting() {
        meetingPaused.value = true
        startService(Intent(this, MeetingRecorderService::class.java).apply { action = MeetingRecorderService.ACTION_PAUSE })
    }
    private fun resumeMeeting() {
        meetingPaused.value = false
        startService(Intent(this, MeetingRecorderService::class.java).apply { action = MeetingRecorderService.ACTION_RESUME })
    }
    private fun stopMeeting() {
        meetingRecording.value = false
        meetingPaused.value = false
        startService(Intent(this, MeetingRecorderService::class.java).apply { action = MeetingRecorderService.ACTION_STOP })
    }
    private fun takeMeetingPhoto() = photoLauncher.launch(null)

    private fun openAccessibilitySettings() {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    private fun openReceivedFile(file: ReceivedFile) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(file.uri, "*/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, file.name))
    }

    private fun queryName(uri: Uri): String {
        var name = uri.lastPathSegment ?: "file"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) name = c.getString(idx)
            }
        }
        return name
    }

    private fun querySize(uri: Uri): Long {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(OpenableColumns.SIZE)
                if (idx >= 0) return c.getLong(idx)
            }
        }
        return -1
    }

    private fun startScreenShare() {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        captureLauncher.launch(mpm.createScreenCaptureIntent())
    }

    private fun stopScreenShare() {
        startService(Intent(this, ScreenShareService::class.java).apply { action = ScreenShareService.ACTION_STOP })
        sharing.value = false
    }

    private fun currentClipboard(): String {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        return cm.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString().orEmpty()
    }

    // ---- Real shared clipboard (auto-sync when the app is in the foreground) ----
    private val clipboard by lazy { getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager }
    private var suppressClip: String? = null

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
        if (!text.isNullOrEmpty() && text != suppressClip) {
            suppressClip = text
            link.sendClipboard(text)
        }
    }

    override fun onResume() {
        super.onResume()
        meetingRecording.value = MeetingRecorderService.activeMeetingId != null
        clipboard.addPrimaryClipChangedListener(clipListener)
        // Do not auto-write peer clipboard here: it can overwrite text the user just copied on Android.
        // Incoming clipboard can still be copied explicitly from its notification.
    }

    override fun onPause() {
        super.onPause()
        clipboard.removePrimaryClipChangedListener(clipListener)
    }

    /** Called when a clipboard update arrives from the peer — write it to the system clipboard. */
    fun onClipReceived(text: String) {
        // Keep UI state only. Writing here races with user copies and can make Push clipboard send stale peer text.
    }

    // ---- Share target: appear in the Android share sheet; forward shared files/text to the peer ----
    private val pendingLock = Any()
    private val pendingFiles = mutableListOf<Uri>()
    private val pendingTexts = mutableListOf<String>()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShare(intent)
        if (intent.action == ACTION_REQUEST_SCREEN_SHARE) startScreenShare()
    }

    private fun handleShare(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain") {
                    intent.getStringExtra(Intent.EXTRA_TEXT)?.let { enqueueText(it) }
                } else {
                    androidx.core.content.IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { enqueueFileUri(it) }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                androidx.core.content.IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.forEach { enqueueFileUri(it) }
            }
        }
    }

    private fun enqueueText(text: String) {
        synchronized(pendingLock) { pendingTexts.add(text) }
        flushPending()
    }

    private fun enqueueFileUri(uri: Uri) {
        synchronized(pendingLock) { pendingFiles.add(uri) }
        flushPending()
    }

    private fun flushPending() {
        if (!link.connected) return
        val files: List<Uri>
        val texts: List<String>
        synchronized(pendingLock) {
            files = pendingFiles.toList(); pendingFiles.clear()
            texts = pendingTexts.toList(); pendingTexts.clear()
        }
        lifecycleScope.launch(Dispatchers.IO) {
            files.forEach { uri -> contentResolver.openInputStream(uri)?.let { link.sendFileStream(queryName(uri), querySize(uri), it) } }
            texts.forEach { link.sendClipboard(it) }
        }
    }

    companion object {
        const val ACTION_REQUEST_SCREEN_SHARE = "com.androidbridge.REQUEST_SCREEN_SHARE"
    }
}

@Composable
private fun HomeScreen(
    link: LinkManager,
    readClipboard: () -> String,
    sharing: Boolean,
    meetingRecording: Boolean,
    meetingPaused: Boolean,
    onStartShare: () -> Unit,
    onStopShare: () -> Unit,
    onStartMeeting: () -> Unit,
    onPauseMeeting: () -> Unit,
    onResumeMeeting: () -> Unit,
    onStopMeeting: () -> Unit,
    onTakeMeetingPhoto: () -> Unit,
    onPickFile: () -> Unit,
    onOpenReceivedFile: (ReceivedFile) -> Unit,
    onOpenAccessibilitySettings: () -> Unit,
    onClipReceived: (String) -> Unit,
) {
    val status by link.status.collectAsState()
    val nearby by link.nearby.collectAsState()
    val paired by link.pairedFingerprints.collectAsState()
    val lastClip by link.lastClipboard.collectAsState()
    val events by link.events.collectAsState()
    val peerScreen by link.peerScreen.collectAsState()
    val receivedFiles by link.receivedFiles.collectAsState()
    val connected = status == ConnectionState.CONNECTED
    val activityExpanded = remember { mutableStateOf(false) }
    val macFullScreen = remember { mutableStateOf(false) }
    val selectedTab = remember { mutableStateOf(0) }

    LaunchedEffect(lastClip) { lastClip?.let(onClipReceived) }

    if (macFullScreen.value && peerScreen != null) {
        MacScreenView(link, peerScreen!!, fullScreen = true, onFullScreen = { macFullScreen.value = false })
        return
    }

    if (selectedTab.value == 2) {
        SecondBrainCard(link, connected, onExit = { selectedTab.value = 0 })
        return
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Fixed header (does not scroll)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
                .background(MaterialTheme.colorScheme.background)
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            Box(
                Modifier.size(38.dp).background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center,
            ) { Text("⟷", fontSize = 20.sp, color = MaterialTheme.colorScheme.onPrimaryContainer) }
            Spacer(Modifier.size(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Android Bridge", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
                Text("Continuity hub", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
            }
            StatusPill(status)
        }

        TabRow(selectedTabIndex = selectedTab.value) {
            Tab(selected = selectedTab.value == 0, onClick = { selectedTab.value = 0 }, text = { Text("Bridge") })
            Tab(selected = selectedTab.value == 1, onClick = { selectedTab.value = 1 }, text = { Text("Notes") })
            Tab(selected = selectedTab.value == 2, onClick = { selectedTab.value = 2 }, text = { Text("Brain") })
        }

        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
        if (selectedTab.value == 1) {
            MeetingCaptureCard(connected, meetingRecording, meetingPaused, onStartMeeting, onPauseMeeting, onResumeMeeting, onStopMeeting, onTakeMeetingPhoto)
            Text("Past meetings, transcripts, summaries, audio, photos, and Q&A are managed on the Mac Notes tab.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        } else {
        SectionCard("This device") {
            Text(Build.MODEL ?: "Android", color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Medium)
            Text("Fingerprint ${link.fingerprint.take(20)}…", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }

        SectionCard("Nearby devices") {
            if (nearby.isEmpty()) {
                Text("Searching the local network…", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            } else {
                nearby.forEach { peer -> NearbyRow(peer, peer.fingerprint in paired) { link.pair(peer) } }
            }
        }

        if (peerScreen != null) {
            SectionCard("Mac screen") {
                MacScreenView(link, peerScreen!!, fullScreen = false, onFullScreen = { macFullScreen.value = true })
            }
        }

        SectionCard("Screen sharing & control") {
            Text(if (connected) "Mirror this phone's screen to the Mac. Remote control requires enabling Android Bridge in Accessibility once." else "Connect a device first.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            if (sharing) {
                Button(onClick = onStopShare, modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF4444))) { Text("Stop sharing") }
            } else {
                Button(onClick = onStartShare, enabled = connected, modifier = Modifier.fillMaxWidth()) { Text("Start screen share") }
            }
            OutlinedButton(onClick = onOpenAccessibilitySettings, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                Text("Enable Mac control")
            }
        }

        SectionCard("Meeting Notes") {
            Text("Open the Notes tab to record/pause/resume, capture photos, and watch meeting status.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        }

        SectionCard("Clipboard & files") {
            Text(if (connected) "Share clipboard text or send a file — both ways." else "Pair a device to enable.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Chip("Push clipboard", connected, Modifier.weight(1f)) { link.sendClipboard(readClipboard()) }
                Chip("Send file", connected, Modifier.weight(1f)) { onPickFile() }
            }
            if (receivedFiles.isNotEmpty()) {
                Text("Received from Mac", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                receivedFiles.forEach { file ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text(file.name, color = MaterialTheme.colorScheme.onSurface, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        OutlinedButton(onClick = { onOpenReceivedFile(file) }, shape = RoundedCornerShape(12.dp)) { Text("Open") }
                    }
                }
            }
        }

        SectionCard("Test features") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                Chip("Notification", connected, Modifier.weight(1f)) { link.sendTestNotification() }
                Chip("SMS", connected, Modifier.weight(1f)) { link.sendTestSms() }
                Chip("Call", connected, Modifier.weight(1f)) { link.sendTestCall() }
            }
        }

        SectionCard("Activity") {
            OutlinedButton(onClick = { activityExpanded.value = !activityExpanded.value }, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth()) {
                Text(if (activityExpanded.value) "Hide activity" else "Show activity")
            }
            if (activityExpanded.value) {
                if (events.isEmpty()) {
                    Text("Nothing yet — clipboard: ${lastClip ?: "—"}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                } else {
                    events.forEach { e -> Text(e, color = MaterialTheme.colorScheme.onSurface, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                }
            }
        }
        }
        } // end scrollable content
    }
}

@Composable
private fun SecondBrainCard(link: LinkManager, connected: Boolean, onExit: () -> Unit) {
    val nodes by link.brainNodes.collectAsState()
    val path by link.selectedBrainPath.collectAsState()
    val content by link.selectedBrainContent.collectAsState()
    val status by link.brainStatus.collectAsState()
    val results by link.brainSearchResults.collectAsState()
    var editText by remember(content) { mutableStateOf(content) }
    var query by remember { mutableStateOf("") }
    var drawerOpen by remember { mutableStateOf(path.isBlank()) }
    var rawMode by remember { mutableStateOf(false) }
    var expandedFolders by remember { mutableStateOf(emptySet<String>()) }
    val shown = if (query.isNotBlank()) {
        results.take(40)
    } else {
        nodes.filter { node -> folderAncestors(node.path).all(expandedFolders::contains) }
    }
    val bg = Color(0xFF1E1E1E)
    val panel = Color(0xFF262626)
    val line = Color(0xFF3A3A3A)
    val text = Color(0xFFE6E1F0)
    val muted = Color(0xFFAAA3B7)
    val purple = Color(0xFF8F7CF8)
    val hasFolder by link.brainHasFolder.collectAsState()
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let { link.setBrainFolder(it) }
    }

    LaunchedEffect(hasFolder) { if (hasFolder) link.refreshSecondBrain() }

    Box(Modifier.fillMaxSize().background(bg)) {
        if (!hasFolder) {
            Column(
                Modifier.fillMaxSize().padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Second Brain", color = text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.size(12.dp))
                Text(
                    "Choose the Syncthing folder that holds your notes. Syncthing keeps it synced with your Mac and home server.",
                    color = muted, fontSize = 14.sp, textAlign = TextAlign.Center,
                )
                Spacer(Modifier.size(20.dp))
                Button(onClick = { folderPicker.launch(null) }) { Text("Choose Syncthing folder") }
                Spacer(Modifier.size(12.dp))
                Text("Close", color = muted, fontSize = 14.sp, modifier = Modifier.clickable(onClick = onExit).padding(8.dp))
            }
            return@Box
        }
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().background(panel).padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(if (drawerOpen) "‹" else "☰", color = text, fontSize = 28.sp, modifier = Modifier.clickable { drawerOpen = !drawerOpen }.padding(6.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (path.isBlank()) "Vault" else path.substringAfterLast('/').removeSuffix(".md"), color = text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (path.isNotBlank()) Text(path, color = muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (path.isNotBlank()) {
                    Text(if (rawMode) "Preview" else "Raw", color = purple, fontSize = 14.sp, modifier = Modifier.clickable { rawMode = !rawMode }.padding(8.dp))
                    Text("Save", color = purple, fontSize = 14.sp, modifier = Modifier.clickable { link.saveSecondBrainNode(path, editText) }.padding(8.dp))
                }
                Text("×", color = muted, fontSize = 26.sp, modifier = Modifier.clickable(onClick = onExit).padding(6.dp))
            }

            if (path.isBlank()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Open the menu to choose a note", color = muted)
                }
            } else if (rawMode) {
                OutlinedTextField(
                    value = editText,
                    onValueChange = { editText = it },
                    modifier = Modifier.fillMaxSize().padding(12.dp),
                    textStyle = androidx.compose.ui.text.TextStyle(color = text, fontSize = 16.sp, lineHeight = 24.sp),
                    label = { Text("Raw markdown") },
                )
            } else {
                Text(
                    editText,
                    color = text,
                    fontSize = 17.sp,
                    lineHeight = 27.sp,
                    modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 18.dp),
                )
            }
        }

        if (drawerOpen) {
            Row(Modifier.fillMaxSize()) {
                Column(
                    Modifier.fillMaxHeight().fillMaxWidth(0.86f).background(panel).padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Vault", color = text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        Text("×", color = muted, fontSize = 28.sp, modifier = Modifier.clickable { drawerOpen = false }.padding(8.dp))
                    }
                    Text(status, color = muted, fontSize = 12.sp)
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it; link.searchSecondBrain(it) },
                        label = { Text("Search files") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        Chip("Refresh", true, Modifier.weight(1f)) { link.refreshSecondBrain() }
                        Chip("New", true, Modifier.weight(1f)) {
                            val newPath = "mobile/${System.currentTimeMillis()}.md"
                            link.saveSecondBrainNode(newPath, "# Mobile note\n")
                            link.selectSecondBrainNode(newPath)
                            rawMode = true
                            drawerOpen = false
                        }
                    }
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                        shown.forEach { node ->
                            val selected = node.path == path
                            val expanded = node.path.trimEnd('/') in expandedFolders
                            Row(
                                modifier = Modifier.fillMaxWidth()
                                    .clip(RoundedCornerShape(7.dp))
                                    .background(if (selected) purple.copy(alpha = 0.2f) else Color.Transparent)
                                    .clickable {
                                        if (node.isDirectory) {
                                            val folder = node.path.trimEnd('/')
                                            expandedFolders = if (expanded) expandedFolders - folder else expandedFolders + folder
                                        } else {
                                            link.selectSecondBrainNode(node.path)
                                            rawMode = false
                                            drawerOpen = false
                                        }
                                    }
                                    .padding(start = (10 + node.depth * 14).dp, end = 10.dp, top = 11.dp, bottom = 11.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(if (node.isDirectory) if (expanded) "▾" else "▸" else "·", color = muted, fontSize = 13.sp)
                                Spacer(Modifier.size(8.dp))
                                Text(node.label, color = if (selected) text else muted, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
                Box(Modifier.fillMaxSize().clickable { drawerOpen = false })
            }
        }
    }
}

private fun folderAncestors(path: String): List<String> {
    val parts = path.trim('/').split('/').dropLast(1)
    return parts.indices.map { parts.take(it + 1).joinToString("/") }
}

@Composable
private fun ObsidianPanel(container: Color, border: Color, content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = container),
        border = BorderStroke(1.dp, border),
        shape = RoundedCornerShape(14.dp),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
    }
}

@Composable
private fun MeetingCaptureCard(
    connected: Boolean,
    meetingRecording: Boolean,
    meetingPaused: Boolean,
    onStartMeeting: () -> Unit,
    onPauseMeeting: () -> Unit,
    onResumeMeeting: () -> Unit,
    onStopMeeting: () -> Unit,
    onTakeMeetingPhoto: () -> Unit,
) {
    SectionCard("Meeting capture") {
        val meetingText = when {
            meetingRecording -> "Recording is running. Chunks are sent to the Mac every minute and when you stop."
            connected -> "Record voice, pause/resume, take timestamped photos, and process notes on the Mac."
            else -> "Pair a Mac before starting meeting capture."
        }
        Text(meetingText, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        if (meetingRecording) {
            val now = remember { mutableStateOf(System.currentTimeMillis()) }
            LaunchedEffect(meetingRecording) {
                while (meetingRecording) {
                    now.value = System.currentTimeMillis()
                    delay(1000)
                }
            }
            Text("Elapsed: ${formatElapsed(now.value - MeetingRecorderService.activeStartedAtMs)}", color = MaterialTheme.colorScheme.onSurface, fontSize = 26.sp, fontWeight = FontWeight.Bold)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(10.dp).background(if (meetingPaused) Amber else Color(0xFFEF4444), CircleShape))
                Text(if (meetingPaused) "Paused" else "Recording now", color = if (meetingPaused) Amber else Color(0xFFEF4444), fontWeight = FontWeight.Bold)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            Chip(if (meetingRecording) "Recording…" else "Start", connected && !meetingRecording, Modifier.weight(1f)) { onStartMeeting() }
            Chip(if (meetingPaused) "Resume" else "Pause", meetingRecording, Modifier.weight(1f)) { if (meetingPaused) onResumeMeeting() else onPauseMeeting() }
            Chip("Stop", meetingRecording, Modifier.weight(1f)) { onStopMeeting() }
        }
        Chip("Take meeting photo", connected && meetingRecording && !meetingPaused, Modifier.fillMaxWidth()) { onTakeMeetingPhoto() }
    }
}

private fun formatElapsed(ms: Long): String {
    val total = (ms.coerceAtLeast(0) / 1000).toInt()
    return "%02d:%02d:%02d".format(total / 3600, (total / 60) % 60, total % 60)
}

@Composable
private fun MacScreenView(link: LinkManager, screen: android.graphics.Bitmap, fullScreen: Boolean, onFullScreen: () -> Unit) {
    val imageSize = remember { mutableStateOf(IntSize.Zero) }
    val shape = if (fullScreen) RoundedCornerShape(0.dp) else RoundedCornerShape(10.dp)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Image(
            bitmap = screen.asImageBitmap(),
            contentDescription = "Mac screen",
            modifier = Modifier
                .fillMaxWidth()
                .then(if (fullScreen) Modifier.fillMaxSize() else Modifier.heightIn(min = 260.dp, max = 520.dp))
                .clip(shape)
                .onSizeChanged { imageSize.value = it }
                .pointerInput(screen, imageSize.value) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val start = down.position
                        var end = start
                        var dragged = false
                        drag(down.id) { change ->
                            dragged = true
                            end = change.position
                            change.consume()
                        }
                        val size = imageSize.value
                        if (size.width > 0 && size.height > 0) {
                            if (dragged) link.sendMacSwipe(start.x, start.y, end.x, end.y, size.width.toFloat(), size.height.toFloat())
                            else link.sendMacTap(start.x, start.y, size.width.toFloat(), size.height.toFloat())
                        }
                    }
                },
            contentScale = ContentScale.Fit,
        )
        OutlinedButton(onClick = onFullScreen, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
            Text(if (fullScreen) "Exit full screen" else "Full screen + control")
        }
    }
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), shape = RoundedCornerShape(16.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface, fontSize = 15.sp)
            content()
        }
    }
}

@Composable
private fun StatusPill(status: ConnectionState) {
    val (color, label) = when (status) {
        ConnectionState.CONNECTED -> Emerald to "connected"
        ConnectionState.CONNECTING, ConnectionState.RECONNECTING -> Amber to "connecting"
        ConnectionState.DISCOVERING -> Slate to "searching"
        ConnectionState.DISCONNECTED -> Slate to "offline"
    }
    Row(verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.background(color.copy(alpha = 0.15f), RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 6.dp)) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        Spacer(Modifier.size(6.dp))
        Text(label, color = color, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun Chip(label: String, enabled: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = enabled, modifier = modifier, shape = RoundedCornerShape(12.dp)) {
        Text(label, fontSize = 13.sp)
    }
}

@Composable
private fun NearbyRow(peer: NearbyPeer, isPaired: Boolean, onPair: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(peer.name, color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Medium)
            Text(peer.fingerprint.take(20) + "…", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (isPaired) Text("Paired ✓", color = Emerald, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        else Button(onClick = onPair, shape = RoundedCornerShape(12.dp)) { Text("Pair") }
    }
}
