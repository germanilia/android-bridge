package com.androidbridge.android

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.androidbridge.core.LinkLogger
import com.androidbridge.feature.Mappers

/**
 * Captures posted notifications (U4 / FR-3.1) and maps them to `notif.posted` messages for the Mac.
 * Read-only in v1. Body content is mapped into the protocol message but never logged (CC-PRIV).
 */
class NotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val message = Mappers.notification(sbn.packageName, title, text, sbn.postTime)
        // In a connected session this is handed to ConnectionManager.send(message).
        LinkLogger.info("notif_captured", mapOf("pkg" to sbn.packageName, "msgType" to message.type))
    }
}
