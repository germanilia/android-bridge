package com.androidbridge.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Build
import android.os.PowerManager
import android.util.Base64
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.ServiceCompat
import com.androidbridge.core.LinkHolder
import com.androidbridge.core.LinkLogger
import java.io.ByteArrayOutputStream

/**
 * Captures the phone screen via MediaProjection and streams downscaled JPEG frames to the paired Mac
 * (U8, live view). Runs as a foreground service of type mediaProjection, as required on Android 14.
 */
class ScreenShareService : Service() {
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastSentAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopCapture()
            stopSelf()
            return START_NOT_STICKY
        }
        if (isRunning) return START_STICKY
        val resultCode = intent?.getIntExtra(EXTRA_CODE, 0) ?: return START_NOT_STICKY
        val data = intent.getParcelableExtra<Intent>(EXTRA_DATA) ?: return START_NOT_STICKY
        if (projection != null) return START_STICKY
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else 0
        ServiceCompat.startForeground(this, NOTIF_ID, buildNotification(), type)
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mp = mpm.getMediaProjection(resultCode, data)
        startCapture(mp)
        return START_STICKY
    }

    private fun startCapture(mp: MediaProjection) {
        projection = mp
        isRunning = true
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.SCREEN_DIM_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE, "AndroidBridge:ScreenShare")
            .also { it.acquire() }

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        val targetW = 480
        val targetH = (targetW.toLong() * metrics.heightPixels / metrics.widthPixels).toInt().coerceAtLeast(1)

        val reader = ImageReader.newInstance(targetW, targetH, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        val ht = HandlerThread("screen-capture").also { it.start() }
        thread = ht
        val handler = Handler(ht.looper)

        mp.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() { stopCapture() }
        }, handler)

        virtualDisplay = try {
            mp.createVirtualDisplay(
                "android_bridge_screen", targetW, targetH, metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.surface, null, handler,
            )
        } catch (e: Exception) {
            LinkLogger.warn("screen_virtual_display_failed", mapOf("err" to (e.message ?: "?")))
            stopCapture()
            stopSelf()
            return
        }

        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val now = System.currentTimeMillis()
                if (now - lastSentAt < FRAME_INTERVAL_MS) return@setOnImageAvailableListener
                lastSentAt = now
                val plane = image.planes[0]
                val rowStride = plane.rowStride
                val pixelStride = plane.pixelStride
                val rowPadding = rowStride - pixelStride * targetW
                val bmp = Bitmap.createBitmap(targetW + rowPadding / pixelStride, targetH, Bitmap.Config.ARGB_8888)
                bmp.copyPixelsFromBuffer(plane.buffer)
                val cropped = Bitmap.createBitmap(bmp, 0, 0, targetW, targetH)
                val out = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 35, out)
                val b64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
                LinkHolder.link?.sendScreenFrame(b64, targetW, targetH)
                bmp.recycle(); cropped.recycle()
            } catch (e: Exception) {
                LinkLogger.warn("screen_frame_error", mapOf("err" to (e.message ?: "?")))
            } finally {
                image.close()
            }
        }, handler)
        LinkLogger.info("screen_capture_started", mapOf("w" to targetW.toString(), "h" to targetH.toString()))
    }

    private fun stopCapture() {
        runCatching { virtualDisplay?.release() }
        runCatching { imageReader?.close() }
        runCatching { projection?.stop() }
        runCatching { thread?.quitSafely() }
        runCatching { wakeLock?.release() }
        virtualDisplay = null; imageReader = null; projection = null; thread = null; wakeLock = null; isRunning = false
    }

    override fun onDestroy() {
        super.onDestroy()
        stopCapture()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Screen sharing", NotificationManager.IMPORTANCE_LOW))
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Android Bridge")
            .setContentText("Sharing your screen")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        const val ACTION_STOP = "stop"
        @Volatile var isRunning = false
        private const val CHANNEL_ID = "screen_share"
        private const val NOTIF_ID = 2002
        private const val FRAME_INTERVAL_MS = 250L // ~4 fps
    }
}
