package com.androidbridge.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import com.androidbridge.core.LinkLogger

/**
 * Keeps the device link alive while the app is backgrounded (U3 / FR-2.2), showing an ongoing
 * status notification. Foreground service type = connectedDevice (declared in the manifest).
 */
class LinkForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        com.androidbridge.core.LinkHolder.ensure(applicationContext)
        LinkLogger.info("foreground_service_started")
        return START_STICKY
    }

    private fun buildNotification(): Notification =
        Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Android Bridge")
            .setContentText("Continuity link active")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()

    private fun createChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, "Link status", NotificationManager.IMPORTANCE_LOW)
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "link_status"
        private const val NOTIFICATION_ID = 1001
    }
}
