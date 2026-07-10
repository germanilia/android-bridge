package com.androidbridge.feature

/** Clipboard sync behavior (FR-6.2 / US-6.2). Default = MANUAL per the decision in Units Generation. */
enum class ClipboardSyncMode { MANUAL, AUTO }

/**
 * Decides whether a local clipboard change should be pushed to the peer. With MANUAL (the default),
 * only an explicit user push sends; with AUTO, any local copy syncs. Pure logic — JVM-testable.
 */
class ClipboardSyncPolicy(var mode: ClipboardSyncMode = ClipboardSyncMode.MANUAL) {

    /** @param userInitiated true when the user explicitly hit "push clipboard". */
    fun shouldSend(userInitiated: Boolean): Boolean = when (mode) {
        ClipboardSyncMode.AUTO -> true
        ClipboardSyncMode.MANUAL -> userInitiated
    }
}
