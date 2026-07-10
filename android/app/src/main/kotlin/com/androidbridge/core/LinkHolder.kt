package com.androidbridge.core

import android.content.Context
import android.os.Build
import com.androidbridge.android.AndroidSecureStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Process-wide link owner shared by the foreground service, activity, and screen-capture service. */
object LinkHolder {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @Volatile
    var link: LinkManager? = null
        private set

    @Synchronized
    fun ensure(context: Context): LinkManager {
        link?.let { return it }
        val appContext = context.applicationContext
        val store = AndroidSecureStore(appContext)
        val name = Build.MODEL ?: "Android"
        val identity = CertIdentityStore.loadOrCreate(store, name)
        val manager = LinkManager(appContext, name, identity, store, scope)
        manager.start()
        link = manager
        return manager
    }
}
