package com.androidbridge.android

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent

class ClipboardCopyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra(EXTRA_TEXT) ?: return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Android Bridge", text))
    }

    companion object {
        const val ACTION_COPY_CLIPBOARD = "com.androidbridge.COPY_CLIPBOARD"
        const val EXTRA_TEXT = "text"
    }
}
