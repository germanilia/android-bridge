package com.androidbridge.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import com.androidbridge.core.LinkHolder

/**
 * Forwards call lifecycle to the paired Mac so it can show a ringing panel and then an in-call
 * panel: RINGING → call.incoming, OFFHOOK → call.state("active"), IDLE → call.state("ended").
 *
 * The RINGING broadcast can fire twice — once without the number and once with it (the latter
 * only when READ_CALL_LOG is granted; some OEMs never send it). Forward both; the Mac replaces
 * its panel, so the second broadcast just fills in the number. OFFHOOK/IDLE carry no number, so
 * we reuse the last ringing number/name (the Mac trusts its own tracked call for outgoing dials).
 */
class CallStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val link = LinkHolder.link ?: return
        when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
                val contactName = if (number.isBlank()) null else lookupContactName(context, number)
                lastNumber = number
                lastName = contactName
                link.sendIncomingCall(number, contactName)
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> link.sendCallState("active", lastNumber, lastName)
            TelephonyManager.EXTRA_STATE_IDLE -> {
                link.sendCallState("ended", lastNumber, lastName)
                lastNumber = ""
                lastName = null
            }
        }
    }

    private fun lookupContactName(context: Context, number: String): String? {
        if (context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        val uri = android.net.Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, android.net.Uri.encode(number))
        val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            return cursor.getString(0)
        }
        return null
    }

    // The RINGING broadcast carries the number; OFFHOOK/IDLE do not, so we carry it forward.
    // LinkManager also reads these to report a call already in progress when the link connects.
    companion object {
        var lastNumber = ""
        var lastName: String? = null
    }
}
