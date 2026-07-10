package com.androidbridge.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.androidbridge.core.LinkLogger

/**
 * mDNS/Bonjour discovery via Android [NsdManager] (U3 / FR-2.1). Advertises this device and browses
 * for the paired peer. Network-dependent — compiled here, exercised on-device (not unit-tested).
 */
class NsdDiscovery(context: Context) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    fun startBrowsing(onPeerFound: (host: String, port: Int) -> Unit) {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                LinkLogger.warn("nsd_discovery_failed", mapOf("code" to errorCode.toString()))
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStarted(serviceType: String) {
                LinkLogger.info("nsd_discovery_started")
            }
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                nsd.resolveService(service, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        val host = serviceInfo.host?.hostAddress ?: return
                        onPeerFound(host, serviceInfo.port)
                    }
                })
            }
            override fun onServiceLost(service: NsdServiceInfo) {
                LinkLogger.info("nsd_service_lost")
            }
        }
        discoveryListener = listener
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stop() {
        discoveryListener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discoveryListener = null
    }

    companion object {
        const val SERVICE_TYPE = "_androidbridge._tcp."
    }
}
