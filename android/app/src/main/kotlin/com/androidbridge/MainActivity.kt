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
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
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
import android.widget.Toast
import com.androidbridge.core.MdBlock
import com.androidbridge.core.NoteLink
import com.androidbridge.core.parseMarkdown
import com.androidbridge.core.resolveNoteLink
import com.androidbridge.core.NearbyPeer
import com.androidbridge.core.ReceivedFile
import com.androidbridge.update.AndroidUpdate
import com.androidbridge.update.AndroidUpdateCoordinator
import com.androidbridge.update.AndroidUpdateUiState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    private lateinit var updates: AndroidUpdateCoordinator
    private var updateJob: Job? = null
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
        updates = AndroidUpdateCoordinator(applicationContext)
        setContent {
            val updateState by updates.state.collectAsState()
            MaterialTheme(colorScheme = BrandScheme) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    HomeScreen(link, ::currentClipboard, sharing.value, meetingRecording.value, meetingPaused.value, ::startScreenShare, ::stopScreenShare, ::startMeeting, ::pauseMeeting, ::resumeMeeting, ::stopMeeting, ::takeMeetingPhoto, ::pickFile, ::openReceivedFile, ::openAccessibilitySettings, updateState, AndroidUpdateActions(::checkForUpdates, ::confirmUpdate, ::dismissUpdate, ::openReleasePage))
                }
            }
        }
        startAutomaticUpdateCheck()
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

    private fun checkForUpdates() = startUpdateOperation { updates.check(manual = true) }
    private fun confirmUpdate(update: AndroidUpdate) = startUpdateOperation { updates.downloadAndInstall(update) }
    private fun dismissUpdate() {
        updateJob?.cancel()
        updates.cancel()
    }

    private fun startAutomaticUpdateCheck() = startUpdateOperation {
        if (withContext(Dispatchers.IO) { updates.cleanStale() }) updates.check(manual = false)
    }

    private fun startUpdateOperation(operation: suspend () -> Unit) {
        updateJob?.cancel()
        updateJob = lifecycleScope.launch { operation() }
    }
    private fun openReleasePage(url: String) = startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

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

    // Android permits clipboard observation only while this activity is foregrounded.
    private val clipboard by lazy { getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager }

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
        if (!text.isNullOrEmpty()) link.sendClipboard(text, userInitiated = false)
    }

    override fun onResume() {
        super.onResume()
        meetingRecording.value = MeetingRecorderService.activeMeetingId != null
        clipboard.addPrimaryClipChangedListener(clipListener)
    }

    override fun onPause() {
        super.onPause()
        clipboard.removePrimaryClipChangedListener(clipListener)
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
    updateState: AndroidUpdateUiState,
    updateActions: AndroidUpdateActions,
) {
    val status by link.status.collectAsState()
    val nearby by link.nearby.collectAsState()
    val paired by link.pairedFingerprints.collectAsState()
    val lastClip by link.lastClipboard.collectAsState()
    val clipboardAutoSync by link.clipboardAutoSync.collectAsState()
    val events by link.events.collectAsState()
    val peerScreen by link.peerScreen.collectAsState()
    val receivedFiles by link.receivedFiles.collectAsState()
    val connected = status == ConnectionState.CONNECTED
    val activityExpanded = remember { mutableStateOf(false) }
    val macFullScreen = remember { mutableStateOf(false) }
    val selectedTab = remember { mutableStateOf(0) }

    if (macFullScreen.value && peerScreen != null) {
        MacScreenView(link, peerScreen!!, fullScreen = true, onFullScreen = { macFullScreen.value = false })
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
            Tab(selected = selectedTab.value == 1, onClick = { selectedTab.value = 1 }, text = { Text("Meetings") })
            Tab(selected = selectedTab.value == 2, onClick = { selectedTab.value = 2 }, text = { Text("Brain") })
            Tab(selected = selectedTab.value == 3, onClick = { selectedTab.value = 3 }, text = { Text("Settings") })
        }

        if (selectedTab.value == 2) {
            SecondBrainCard(link, onExit = { selectedTab.value = 0 })
        } else if (selectedTab.value == 1) {
            MeetingsScreen(
                link = link,
                connected = connected,
                recording = meetingRecording,
                paused = meetingPaused,
                onStart = onStartMeeting,
                onPause = onPauseMeeting,
                onResume = onResumeMeeting,
                onStop = onStopMeeting,
                onPhoto = onTakeMeetingPhoto,
                onExit = { selectedTab.value = 0 },
            )
        } else {
        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
        if (selectedTab.value == 3) {
            UpdateSettingsCard(updateState, updateActions)
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

        SectionCard("Meetings") {
            Text("Open the Meetings tab to record in person and review all synced meeting content.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        }

        SectionCard("Clipboard & files") {
            Text(
                if (!connected) "Pair a device to enable clipboard and files."
                else if (clipboardAutoSync) "Clipboard text syncs automatically while Android Bridge is open."
                else "Clipboard sharing is manual until Auto Sync is enabled.",
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp,
            )
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Auto Sync clipboard", modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurface)
                Switch(checked = clipboardAutoSync, onCheckedChange = link::setClipboardAutoSync)
            }
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
                    Text(if (lastClip == null) "Nothing yet" else "Clipboard received", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                } else {
                    events.forEach { e -> Text(e, color = MaterialTheme.colorScheme.onSurface, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                }
            }
        }
        }
        } // end scrollable content
        }
    }
    UpdateDialogs(updateState, updateActions)
}

@Composable
private fun MeetingsScreen(
    link: LinkManager,
    connected: Boolean,
    recording: Boolean,
    paused: Boolean,
    onStart: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onPhoto: () -> Unit,
    onExit: () -> Unit,
) {
    val nodes by link.brainNodes.collectAsState()
    val content by link.selectedBrainContent.collectAsState()
    val loading by link.brainNoteLoading.collectAsState()
    val refreshing by link.brainRefreshing.collectAsState()
    var openPath by rememberSaveable { mutableStateOf<String?>(null) }
    val meetings = remember(nodes) {
        nodes.filter { !it.isDirectory && isMirroredMeetingNote(it.path) }
            .sortedByDescending { it.modifiedAt }
    }

    LaunchedEffect(Unit) { link.refreshSecondBrain() }
    BackHandler {
        if (openPath == null) onExit() else openPath = null
    }

    if (openPath != null) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = { openPath = null }) { Text("Back") }
                Text(
                    displayBrainLabel(openPath!!.substringAfterLast('/')),
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            }
            if (loading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else {
                MarkdownView(
                    markdown = content,
                    text = MaterialTheme.colorScheme.onSurface,
                    muted = MaterialTheme.colorScheme.onSurfaceVariant,
                    codeBg = MaterialTheme.colorScheme.surfaceVariant,
                    accent = MaterialTheme.colorScheme.primary,
                    onLink = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 14.dp),
    ) {
        item {
            MeetingCaptureCard(connected, recording, paused, onStart, onPause, onResume, onStop, onPhoto)
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f)) {
                    Text("Past meetings", color = MaterialTheme.colorScheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Text("Summaries and transcripts sync here. Recordings stay on the Mac.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                }
                if (refreshing) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                } else {
                    TextButton(onClick = { link.refreshSecondBrain() }) { Text("Refresh") }
                }
            }
        }
        if (meetings.isEmpty() && !refreshing) {
            item {
                SectionCard("No synced meetings") {
                    Text("Keep Syncthing running on the Mac and phone. Meeting text appears here automatically.", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                }
            }
        }
        items(meetings, key = { it.path }) { note ->
            Card(
                modifier = Modifier.fillMaxWidth().clickable {
                    link.selectSecondBrainNode(note.path)
                    openPath = note.path
                },
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                shape = RoundedCornerShape(14.dp),
            ) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(displayBrainLabel(note.label), color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text("Summary • Transcript • Q&A", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    }
                    Text("Open", color = MaterialTheme.colorScheme.primary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun UpdateSettingsCard(state: AndroidUpdateUiState, actions: AndroidUpdateActions) {
    val checking = state is AndroidUpdateUiState.Checking
    val downloading = state is AndroidUpdateUiState.Downloading
    SectionCard("App updates") {
        val context = LocalContext.current
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        Text("Installed version ${packageInfo.versionName}", color = MaterialTheme.colorScheme.onSurface)
        Text(updateStatus(state), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        if (checking || downloading) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                Text(if (checking) "Checking for updates" else "Downloading and verifying update")
            }
        }
        if (state is AndroidUpdateUiState.Available) {
            Text("Version ${state.update.bundle.version} is available.", color = MaterialTheme.colorScheme.onSurface)
            OutlinedButton(onClick = { actions.openReleasePage(state.update.bundle.releasePage) }, modifier = Modifier.fillMaxWidth()) {
                Text("Open release page")
            }
        }
        Button(onClick = actions.check, enabled = !checking && !downloading, modifier = Modifier.fillMaxWidth()) {
            Text("Check for updates")
        }
    }
}

@Composable
private fun UpdateDialogs(state: AndroidUpdateUiState, actions: AndroidUpdateActions) {
    when (state) {
        is AndroidUpdateUiState.Available -> AlertDialog(
            onDismissRequest = actions.dismiss,
            title = { Text("Update available") },
            text = { Text("Version ${state.update.bundle.version} is ready to download. Android will ask for installation approval after verification.") },
            confirmButton = { Button(onClick = { actions.download(state.update) }) { Text("Download") } },
            dismissButton = { OutlinedButton(onClick = actions.dismiss) { Text("Not now") } },
        )
        AndroidUpdateUiState.Downloading -> AlertDialog(
            onDismissRequest = actions.dismiss,
            title = { Text("Downloading update") },
            text = { Text("Downloading and verifying the update.") },
            confirmButton = {},
            dismissButton = { OutlinedButton(onClick = actions.dismiss) { Text("Cancel") } },
        )
        is AndroidUpdateUiState.Error -> AlertDialog(
            onDismissRequest = actions.dismiss,
            title = { Text("Update unavailable") },
            text = { Text(state.message) },
            confirmButton = { Button(onClick = actions.dismiss) { Text("OK") } },
        )
        else -> Unit
    }
}

private fun updateStatus(state: AndroidUpdateUiState): String = when (state) {
    AndroidUpdateUiState.Idle -> "Automatic update checks run in the background."
    is AndroidUpdateUiState.Checking -> "Checking for updates."
    is AndroidUpdateUiState.Available -> "Update available."
    AndroidUpdateUiState.Downloading -> "Downloading and verifying update."
    AndroidUpdateUiState.InstallerLaunched -> "The Android installer is open."
    is AndroidUpdateUiState.Error -> state.message
    AndroidUpdateUiState.UpToDate -> "You have the latest stable version."
}

data class AndroidUpdateActions(
    val check: () -> Unit,
    val download: (AndroidUpdate) -> Unit,
    val dismiss: () -> Unit,
    val openReleasePage: (String) -> Unit,
)

internal enum class SecondBrainDestination { LIBRARY, PREVIEW, EDITOR }

internal sealed interface SecondBrainBack {
    data object Bridge : SecondBrainBack
    data object Library : SecondBrainBack
    data object Preview : SecondBrainBack
    data object ConfirmDiscard : SecondBrainBack
}

internal fun secondBrainBack(destination: SecondBrainDestination, dirty: Boolean): SecondBrainBack = when (destination) {
    SecondBrainDestination.LIBRARY -> SecondBrainBack.Bridge
    SecondBrainDestination.PREVIEW -> if (dirty) SecondBrainBack.ConfirmDiscard else SecondBrainBack.Library
    SecondBrainDestination.EDITOR -> if (dirty) SecondBrainBack.ConfirmDiscard else SecondBrainBack.Preview
}

internal fun displayBrainLabel(fileName: String): String {
    val base = fileName.removeSuffix(".md")
    if (base.equals("index", ignoreCase = true)) return "Overview"
    val words = base.replace(Regex("[-_]+"), " ").trim()
    return words.replaceFirstChar { it.uppercase() }
}

internal fun isMirroredMeetingNote(path: String): Boolean =
    path.startsWith("meetings/android-bridge/") && path.endsWith(".md") && !path.endsWith("/index.md")

@Composable
private fun SecondBrainCard(link: LinkManager, onExit: () -> Unit) {
    val nodes by link.brainNodes.collectAsState()
    val path by link.selectedBrainPath.collectAsState()
    val content by link.selectedBrainContent.collectAsState()
    val status by link.brainStatus.collectAsState()
    val results by link.brainSearchResults.collectAsState()
    val conflicts by link.brainConflicts.collectAsState()
    val folderName by link.brainFolderName.collectAsState()
    val refreshing by link.brainRefreshing.collectAsState()
    val noteLoading by link.brainNoteLoading.collectAsState()
    var editText by remember { mutableStateOf(content) }
    var editDirty by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var drawerOpen by remember { mutableStateOf(path.isBlank()) }
    var rawMode by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var discardToLibrary by remember { mutableStateOf(false) }
    var expandedJoined by rememberSaveable { mutableStateOf("") }
    val expandedFolders = remember(expandedJoined) { expandedJoined.split('\n').filter { it.isNotEmpty() }.toSet() }
    val treeNodes = remember(nodes, expandedFolders) {
        nodes.filter { node ->
            node.label.trim().trim('.').isNotEmpty() && folderAncestors(node.path).all(expandedFolders::contains)
        }
    }
    val folderNoteCounts = remember(nodes) {
        val counts = HashMap<String, Int>()
        for (node in nodes) {
            if (node.isDirectory) continue
            for (ancestor in folderAncestors(node.path)) counts[ancestor] = (counts[ancestor] ?: 0) + 1
        }
        counts
    }
    val bg = MaterialTheme.colorScheme.background
    val panel = MaterialTheme.colorScheme.surface
    val text = MaterialTheme.colorScheme.onSurface
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val purple = MaterialTheme.colorScheme.primary
    val hasFolder by link.brainHasFolder.collectAsState()
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let { link.setBrainFolder(it) }
    }
    val context = LocalContext.current
    val openLink: (String) -> Unit = { target ->
        when (val resolved = resolveNoteLink(target, path)) {
            is NoteLink.External -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(resolved.url)))
            is NoteLink.Note -> {
                // Index notes sometimes link relative to the brain root instead of the note.
                val candidates = listOf(resolved.path, (resolveNoteLink("/$target", path) as NoteLink.Note).path)
                val found = candidates.firstOrNull { candidate -> nodes.any { !it.isDirectory && it.path == candidate } }
                if (found != null) {
                    link.selectSecondBrainNode(found)
                    rawMode = false
                } else {
                    Toast.makeText(context, "Note not found: ${resolved.path}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    LaunchedEffect(path) { editDirty = false }
    LaunchedEffect(content) { if (!editDirty) editText = content }
    LaunchedEffect(hasFolder) {
        if (hasFolder) link.refreshSecondBrain(refreshSelectedContent = !editDirty)
    }

    val navigateBack = {
        val destination = when {
            drawerOpen -> SecondBrainDestination.LIBRARY
            rawMode -> SecondBrainDestination.EDITOR
            else -> SecondBrainDestination.PREVIEW
        }
        when (secondBrainBack(destination, editDirty)) {
            SecondBrainBack.Bridge -> onExit()
            SecondBrainBack.Library -> drawerOpen = true
            SecondBrainBack.Preview -> rawMode = false
            SecondBrainBack.ConfirmDiscard -> {
                discardToLibrary = destination == SecondBrainDestination.PREVIEW
                confirmDiscard = true
            }
        }
    }
    BackHandler(onBack = navigateBack)

    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Discard unsaved changes?") },
            text = { Text("Your edits to this note have not been saved.") },
            confirmButton = {
                TextButton(onClick = {
                    editText = content
                    editDirty = false
                    rawMode = false
                    drawerOpen = discardToLibrary
                    confirmDiscard = false
                }) { Text("Discard") }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Keep editing") } },
        )
    }

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
            }
            return@Box
        }
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().background(panel).padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TextButton(onClick = navigateBack) { Text("Back") }
                Column(Modifier.weight(1f)) {
                    Text(if (path.isBlank()) "Second Brain" else displayBrainLabel(path.substringAfterLast('/')), color = text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(if (path.isBlank()) "$folderName • $status" else path, color = muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (path.isNotBlank()) {
                    TextButton(onClick = { rawMode = !rawMode }) { Text(if (rawMode) "Preview" else "Edit") }
                    if (rawMode) {
                        TextButton(
                            enabled = editDirty,
                            onClick = { link.saveSecondBrainNode(path, editText) { saved -> if (saved) editDirty = false } },
                        ) { Text("Save") }
                    }
                }
            }

            if (path.isBlank()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Choose a note from the library", color = muted)
                }
            } else if (noteLoading) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (rawMode) {
                OutlinedTextField(
                    value = editText,
                    onValueChange = { editText = it; editDirty = true },
                    modifier = Modifier.fillMaxSize().padding(12.dp),
                    textStyle = androidx.compose.ui.text.TextStyle(color = text, fontSize = 16.sp, lineHeight = 24.sp),
                    label = { Text("Raw markdown") },
                )
            } else {
                MarkdownView(
                    markdown = editText,
                    text = text,
                    muted = muted,
                    codeBg = bg,
                    accent = purple,
                    onLink = openLink,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        if (drawerOpen) {
            Row(Modifier.fillMaxSize()) {
                Column(
                    Modifier.fillMaxHeight().fillMaxWidth().background(bg).padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Second Brain", color = text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                            Text("$folderName • $status", color = muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        if (refreshing) {
                            CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        } else {
                            TextButton(onClick = { link.refreshSecondBrain() }) { Text("Refresh") }
                        }
                    }
                    if (conflicts > 0) {
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(Color(0xFF3A2B2B)).padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                if (conflicts == 1) "1 sync conflict copy" else "$conflicts sync conflict copies",
                                color = Color(0xFFF0B8A8), fontSize = 13.sp, modifier = Modifier.weight(1f),
                            )
                            TextButton(onClick = { link.resolveBrainConflicts() }) { Text("Keep synced") }
                        }
                    }
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it; link.searchSecondBrain(it) },
                        placeholder = { Text("Search notes or #tags") },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(14.dp),
                        singleLine = true,
                    )
                    OutlinedButton(
                        onClick = {
                            val newPath = "mobile/${System.currentTimeMillis()}.md"
                            link.saveSecondBrainNode(newPath, "# Mobile note\n") { saved ->
                                if (saved) {
                                    link.selectSecondBrainNode(newPath)
                                    rawMode = true
                                    drawerOpen = false
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(14.dp),
                    ) { Text("＋  New note") }
                    if (query.isNotBlank()) {
                        LazyColumn(
                            Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(panel).padding(6.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            items(results, key = { it.node.path }) { hit ->
                                Column(
                                    Modifier.fillMaxWidth()
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(if (hit.node.path == path) purple.copy(alpha = 0.2f) else Color.Transparent)
                                        .clickable {
                                            link.selectSecondBrainNode(hit.node.path)
                                            rawMode = false
                                            drawerOpen = false
                                        }
                                        .padding(horizontal = 10.dp, vertical = 8.dp),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(displayBrainLabel(hit.node.label), color = text, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(hit.node.path.substringBeforeLast('/', ""), color = muted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    if (hit.snippet.isNotBlank()) {
                                        Text(hit.snippet, color = muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                            if (results.isEmpty()) {
                                item { Text("No matches", color = muted, fontSize = 13.sp, modifier = Modifier.padding(10.dp)) }
                            }
                        }
                    } else {
                        LazyColumn(
                            Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(panel).padding(vertical = 6.dp),
                        ) {
                            items(treeNodes, key = { it.path }) { node ->
                                val selected = node.path == path
                                val expanded = node.path.trimEnd('/') in expandedFolders
                                Row(
                                    modifier = Modifier.fillMaxWidth()
                                        .clip(RoundedCornerShape(7.dp))
                                        .background(if (selected) purple.copy(alpha = 0.2f) else Color.Transparent)
                                        .clickable {
                                            if (node.isDirectory) {
                                                val folder = node.path.trimEnd('/')
                                                val next = if (expanded) expandedFolders - folder else expandedFolders + folder
                                                expandedJoined = next.joinToString("\n")
                                            } else {
                                                link.selectSecondBrainNode(node.path)
                                                rawMode = false
                                                drawerOpen = false
                                            }
                                        }
                                        .heightIn(min = 44.dp)
                                        .padding(start = (10 + node.depth * 12).dp, end = 12.dp, top = 6.dp, bottom = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    if (node.isDirectory) {
                                        Text(if (expanded) "▾" else "▸", color = purple, fontSize = 13.sp)
                                        Text(
                                            displayBrainLabel(node.label),
                                            color = text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                                        )
                                        val count = folderNoteCounts[node.path.trimEnd('/')] ?: 0
                                        if (count > 0) Text("$count", color = muted, fontSize = 12.sp)
                                    } else {
                                        Text("·", color = purple, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                                        Text(
                                            displayBrainLabel(node.label),
                                            color = text, fontSize = 15.sp,
                                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.size(0.dp))
            }
        }
    }
}

/**
 * Renders a note's markdown as a LazyColumn of blocks. Lazy layout means only the
 * visible blocks are measured, so opening a very long note no longer freezes the UI
 * the way rendering the whole note in a single Text/TextField did.
 */
@Composable
private fun MarkdownView(
    markdown: String,
    text: Color,
    muted: Color,
    codeBg: Color,
    accent: Color,
    onLink: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val blocks = remember(markdown) { parseMarkdown(markdown) }
    LazyColumn(
        modifier = modifier.padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(blocks) { block -> MarkdownBlock(block, text, muted, codeBg, accent, onLink) }
    }
}

@Composable
private fun MarkdownBlock(block: MdBlock, text: Color, muted: Color, codeBg: Color, accent: Color, onLink: (String) -> Unit) {
    when (block) {
        is MdBlock.Heading -> {
            val size = when (block.level) { 1 -> 26.sp; 2 -> 22.sp; 3 -> 19.sp; else -> 17.sp }
            Text(inlineMarkdown(block.text, accent, onLink), color = text, fontSize = size, fontWeight = FontWeight.Bold, lineHeight = size * 1.3f)
        }
        is MdBlock.Paragraph -> Text(inlineMarkdown(block.text, accent, onLink), color = text, fontSize = 17.sp, lineHeight = 27.sp)
        is MdBlock.ListItem -> Row(
            modifier = Modifier.padding(start = (block.indent * 8).dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("•", color = muted, fontSize = 17.sp, lineHeight = 27.sp)
            Text(inlineMarkdown(block.text, accent, onLink), color = text, fontSize = 17.sp, lineHeight = 27.sp)
        }
        is MdBlock.Quote -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.width(3.dp).heightIn(min = 22.dp).background(accent))
            Text(inlineMarkdown(block.text, accent, onLink), color = muted, fontSize = 17.sp, lineHeight = 27.sp, fontStyle = FontStyle.Italic)
        }
        is MdBlock.Code -> Text(
            block.text,
            color = text,
            fontSize = 14.sp,
            lineHeight = 21.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(codeBg).padding(12.dp),
        )
        is MdBlock.Table -> Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(codeBg).padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            block.rows.forEachIndexed { index, row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { cell ->
                        Text(
                            inlineMarkdown(cell, accent, onLink),
                            color = text,
                            fontSize = 14.sp,
                            fontWeight = if (index == 0) FontWeight.Bold else FontWeight.Normal,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
        is MdBlock.Divider -> Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).background(muted.copy(alpha = 0.3f)).height(1.dp))
    }
}

private val INLINE_MD = Regex("\\*\\*(.+?)\\*\\*|__(.+?)__|`([^`]+)`|\\*(.+?)\\*|_(.+?)_|\\[(.+?)\\]\\(([^)]+)\\)")

/** Styles a single line of markdown inline spans (bold, italic, code, tappable links). */
private fun inlineMarkdown(src: String, accent: Color, onLink: (String) -> Unit): AnnotatedString = buildAnnotatedString {
    var last = 0
    for (m in INLINE_MD.findAll(src)) {
        if (m.range.first > last) append(src.substring(last, m.range.first))
        val g = m.groupValues
        when {
            g[1].isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(g[1]) }
            g[2].isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(g[2]) }
            g[3].isNotEmpty() -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(g[3]) }
            g[4].isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(g[4]) }
            g[5].isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(g[5]) }
            g[6].isNotEmpty() -> {
                val target = g[7]
                withLink(
                    LinkAnnotation.Clickable(
                        tag = target,
                        styles = TextLinkStyles(style = SpanStyle(color = accent, textDecoration = TextDecoration.Underline)),
                    ) { onLink(target) },
                ) { append(g[6]) }
            }
        }
        last = m.range.last + 1
    }
    if (last < src.length) append(src.substring(last))
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
