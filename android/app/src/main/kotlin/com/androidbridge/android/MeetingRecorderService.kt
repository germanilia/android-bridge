package com.androidbridge.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.androidbridge.core.LinkHolder
import java.io.File
import java.util.UUID

class MeetingRecorderService : Service() {
    private var recorder: MediaRecorder? = null
    private var meetingId = ""
    private var sequence = 0
    private var chunkStarted = 0L
    private var currentFile: File? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val mgr = getSystemService(NotificationManager::class.java)
        mgr.createNotificationChannel(NotificationChannel(CHANNEL, "Meeting capture", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startMeeting(intent.getStringExtra(EXTRA_TITLE), intent.getStringExtra(EXTRA_MEETING_ID))
            ACTION_STOP -> stopMeeting()
            ACTION_PAUSE -> pauseMeeting()
            ACTION_RESUME -> resumeMeeting()
        }
        return START_STICKY
    }

    private fun startMeeting(title: String?, requestedMeetingId: String? = null) {
        if (meetingId.isNotEmpty()) return
        meetingId = requestedMeetingId ?: UUID.randomUUID().toString()
        activeMeetingId = meetingId
        activeStartedAtMs = System.currentTimeMillis()
        sequence = 0
        startForeground(4401, notification("Recording meeting"))
        Log.i("AndroidBridge", "meeting.start service id=$meetingId")
        LinkHolder.ensure(applicationContext).sendMeetingStart(meetingId, title)
        startChunk()
    }

    private fun pauseMeeting() {
        if (Build.VERSION.SDK_INT >= 24) recorder?.pause()
        startForeground(4401, notification("Meeting paused"))
    }

    private fun resumeMeeting() {
        if (Build.VERSION.SDK_INT >= 24) recorder?.resume()
        startForeground(4401, notification("Recording meeting"))
    }

    private fun stopMeeting() {
        if (meetingId.isEmpty()) return
        finishChunk(send = true)
        LinkHolder.ensure(applicationContext).sendMeetingStop(meetingId)
        meetingId = ""
        activeMeetingId = null
        activeStartedAtMs = 0
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startChunk() {
        if (meetingId.isEmpty()) return
        chunkStarted = System.currentTimeMillis()
        val file = File(filesDir, "meeting-$meetingId-$sequence.m4a")
        currentFile = file
        recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()
        recorder!!.apply {
            setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(64_000)
            setAudioSamplingRate(44_100)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        handler.postDelayed({ rotateChunk() }, CHUNK_MS)
    }

    private fun rotateChunk() {
        if (meetingId.isEmpty()) return
        finishChunk(send = true)
        sequence += 1
        startChunk()
    }

    private fun finishChunk(send: Boolean) {
        handler.removeCallbacksAndMessages(null)
        val file = currentFile
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        currentFile = null
        if (send && file != null && file.exists() && file.length() > 0) {
            Log.i("AndroidBridge", "meeting.chunk service sequence=$sequence bytes=${file.length()}")
            LinkHolder.ensure(applicationContext).sendMeetingAudioChunk(meetingId, sequence, chunkStarted, System.currentTimeMillis(), file)
        } else {
            file?.delete()
        }
    }

    private fun notification(text: String): Notification = NotificationCompat.Builder(this, CHANNEL)
        .setSmallIcon(android.R.drawable.ic_btn_speak_now)
        .setContentTitle("Android Bridge")
        .setContentText(text)
        .setOngoing(true)
        .build()

    companion object {
        const val ACTION_START = "com.androidbridge.meeting.START"
        const val ACTION_STOP = "com.androidbridge.meeting.STOP"
        const val ACTION_PAUSE = "com.androidbridge.meeting.PAUSE"
        const val ACTION_RESUME = "com.androidbridge.meeting.RESUME"
        const val EXTRA_TITLE = "title"
        const val EXTRA_MEETING_ID = "meetingId"
        @Volatile var activeMeetingId: String? = null
        @Volatile var activeStartedAtMs: Long = 0
        private const val CHANNEL = "meeting_capture"
        private const val CHUNK_MS = 60_000L
    }
}
