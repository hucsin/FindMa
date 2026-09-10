package com.findma.elder.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * 定位策略（DESIGN 7.2）：
 *  1) 优先复用"新鲜缓存"（上次定位时间 < ½ 上报间隔 且精度可接受）；
 *  2) 否则单次定位：GPS 优先（超时 90s），失败补 NETWORK；
 *  3) LOST 模式强制高精度 GPS。
 * 不依赖 GMS，直接用系统 LocationManager。
 */
class LocationProvider(private val ctx: Context) {

    data class Fix(
        val lat: Double,
        val lng: Double,
        val acc: Float,
        val provider: String,
        val timeMs: Long,
    )

    private val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    suspend fun getLocation(highAccuracy: Boolean, maxAgeMs: Long): Fix? {
        if (!hasPermission()) {
            Log.w(TAG, "缺少定位权限")
            return null
        }

        cached(maxAgeMs, highAccuracy)?.let { return it }

        // LOST 模式：强制 GPS 高精度，给足超时
        val gps = requestOnce(LocationManager.GPS_PROVIDER, if (highAccuracy) 90_000L else 45_000L)
        if (gps != null) return gps.toFix()

        // 兜底：网络定位（精度较低，acc 会如实上报，Worker 侧按 150m 门槛过滤）
        val network = requestOnce(LocationManager.NETWORK_PROVIDER, 30_000L)
        return network?.toFix()
    }

    private fun cached(maxAgeMs: Long, highAccuracy: Boolean): Fix? {
        if (maxAgeMs <= 0) return null
        val providers = if (highAccuracy) {
            listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        } else {
            listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
        }
        var best: Location? = null
        for (p in providers) {
            val loc = runCatching { lm.getLastKnownLocation(p) }.getOrNull() ?: continue
            if (System.currentTimeMillis() - loc.time > maxAgeMs) continue
            if (best == null || loc.time > best.time) best = loc
        }
        // 高精度模式下缓存精度太差就重新定位
        if (highAccuracy && best != null && best.accuracy > 200f) return null
        return best?.toFix()
    }

    private suspend fun requestOnce(provider: String, timeoutMs: Long): Location? {
        val enabled = runCatching { lm.isProviderEnabled(provider) }.getOrDefault(false)
        if (!enabled) return null

        return withTimeoutOrNull(timeoutMs) {
            suspendCancellableCoroutine { cont ->
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        runCatching { lm.removeUpdates(this) }
                        if (cont.isActive) cont.resume(location)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

                    override fun onProviderEnabled(provider: String) = Unit

                    override fun onProviderDisabled(provider: String) = Unit
                }

                val ok = runCatching {
                    lm.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
                    true
                }.getOrElse {
                    Log.w(TAG, "requestLocationUpdates($provider) failed", it)
                    false
                }

                if (!ok) {
                    if (cont.isActive) cont.resume(null)
                    return@suspendCancellableCoroutine
                }

                cont.invokeOnCancellation { runCatching { lm.removeUpdates(listener) } }
            }
        }
    }

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun Location.toFix() = Fix(
        lat = latitude,
        lng = longitude,
        acc = if (hasAccuracy()) accuracy else 0f,
        provider = provider ?: "unknown",
        timeMs = time,
    )

    companion object {
        private const val TAG = "FindMaLoc"
    }
}
