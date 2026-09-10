package com.findma.elder.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log

data class NetState(
    val wifi: Boolean,
    val cellular: Boolean,
    val online: Boolean,
) {
    /** 上报给 Worker 的 netType 字段（DESIGN 6.2） */
    fun kind(): String = when {
        wifi -> "wifi"
        cellular -> "cellular"
        else -> "none"
    }
}

/**
 * WiFi / 蜂窝网络监听（DESIGN 7.3 / 9-④）。
 * WiFi 已连接 → 停 VPN（所有 App 正常联网）；蜂窝 → 启动 VPN 守护（仅 FindMa 可联网）。
 */
class NetworkMonitor(private val ctx: Context) {

    private val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var callback: ConnectivityManager.NetworkCallback? = null

    /** 同步读取当前网络状态（用于立刻组包） */
    fun current(): NetState {
        val network = cm.activeNetwork ?: return NetState(false, false, false)
        val caps = cm.getNetworkCapabilities(network) ?: return NetState(false, false, false)
        val online = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        val wifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        val cellular = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        return NetState(wifi, cellular, online)
    }

    /** 开始监听；回调在网络变化时触发（含首次） */
    fun start(onChange: (NetState) -> Unit) {
        if (callback != null) return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                onChange(current())
            }

            override fun onLost(network: Network) {
                onChange(current())
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                onChange(current())
            }
        }
        callback = cb
        runCatching {
            val req = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(req, cb)
        }.onFailure {
            Log.w(TAG, "registerNetworkCallback failed", it)
            callback = null
        }
    }

    fun stop() {
        val cb = callback ?: return
        runCatching { cm.unregisterNetworkCallback(cb) }
        callback = null
    }

    companion object {
        private const val TAG = "FindMaNet"
    }
}
