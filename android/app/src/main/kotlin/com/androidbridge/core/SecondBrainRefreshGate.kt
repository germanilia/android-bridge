package com.androidbridge.core

import java.util.concurrent.atomic.AtomicBoolean

/** Prevents overlapping SAF folder scans triggered by lifecycle and user refreshes. */
class SecondBrainRefreshGate {
    private val refreshing = AtomicBoolean(false)

    fun tryStart(): Boolean = refreshing.compareAndSet(false, true)

    fun finish() {
        check(refreshing.compareAndSet(true, false)) { "Refresh was not active" }
    }
}
