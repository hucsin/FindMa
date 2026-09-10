package com.findma.elder

import android.content.Context
import android.content.SharedPreferences

/**
 * 本地持久化（DESIGN 10：device token 只存手机本地，服务端只存哈希）。
 * 全部字段都是"崩溃/被杀后能恢复调度"所必需的状态。
 */
object Prefs {
    private const val FILE = "findma_prefs"

    private const val K_DEVICE_ID = "device_id"
    private const val K_TOKEN = "token"
    private const val K_BIND_CODE = "bind_code"
    private const val K_MODE = "mode"
    private const val K_INTERVAL = "interval_sec"
    private const val K_NORMAL_INTERVAL = "normal_interval_sec"
    private const val K_LOST_INTERVAL = "lost_interval_sec"
    private const val K_FENCE_ENABLED = "fence_enabled"
    private const val K_SETTINGS_VER = "settings_ver"
    private const val K_NEXT_REPORT_AT = "next_report_at"
    private const val K_LAST_REPORT_AT = "last_report_at"
    private const val K_LAST_ERROR = "last_error"
    private const val K_VPN_DESIRED = "vpn_desired"
    private const val K_BACKOFF_MS = "backoff_ms"
    private const val K_QUEUE = "offline_queue"

    private fun sp(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // ── 身份 ──────────────────────────────────────────────────────────────
    fun deviceId(ctx: Context) = sp(ctx).getString(K_DEVICE_ID, "") ?: ""
    fun token(ctx: Context) = sp(ctx).getString(K_TOKEN, "") ?: ""
    fun bindCode(ctx: Context) = sp(ctx).getString(K_BIND_CODE, "") ?: ""

    fun saveIdentity(ctx: Context, deviceId: String, token: String, bindCode: String) {
        sp(ctx).edit()
            .putString(K_DEVICE_ID, deviceId)
            .putString(K_TOKEN, token)
            .putString(K_BIND_CODE, bindCode)
            .apply()
    }

    fun saveBindCode(ctx: Context, code: String) {
        sp(ctx).edit().putString(K_BIND_CODE, code).apply()
    }

    // ── 配置（服务端下发）─────────────────────────────────────────────────
    fun mode(ctx: Context) = sp(ctx).getString(K_MODE, "NORMAL") ?: "NORMAL"
    fun intervalSec(ctx: Context) = sp(ctx).getInt(K_INTERVAL, DEFAULT_INTERVAL_SEC)
    fun normalIntervalSec(ctx: Context) = sp(ctx).getInt(K_NORMAL_INTERVAL, DEFAULT_INTERVAL_SEC)
    fun lostIntervalSec(ctx: Context) = sp(ctx).getInt(K_LOST_INTERVAL, 60)
    fun fenceEnabled(ctx: Context) = sp(ctx).getBoolean(K_FENCE_ENABLED, true)
    fun settingsVer(ctx: Context) = sp(ctx).getInt(K_SETTINGS_VER, 0)

    fun saveSettings(
        ctx: Context,
        ver: Int,
        mode: String,
        intervalSec: Int,
        normalIntervalSec: Int,
        lostIntervalSec: Int,
        fenceEnabled: Boolean,
    ) {
        sp(ctx).edit()
            .putInt(K_SETTINGS_VER, ver)
            .putString(K_MODE, mode)
            .putInt(K_INTERVAL, intervalSec)
            .putInt(K_NORMAL_INTERVAL, normalIntervalSec)
            .putInt(K_LOST_INTERVAL, lostIntervalSec)
            .putBoolean(K_FENCE_ENABLED, fenceEnabled)
            .apply()
    }

    // ── 运行状态 ──────────────────────────────────────────────────────────
    fun nextReportAt(ctx: Context) = sp(ctx).getLong(K_NEXT_REPORT_AT, 0L)
    fun setNextReportAt(ctx: Context, at: Long) = sp(ctx).edit().putLong(K_NEXT_REPORT_AT, at).apply()

    fun lastReportAt(ctx: Context) = sp(ctx).getLong(K_LAST_REPORT_AT, 0L)
    fun setLastReportAt(ctx: Context, at: Long) = sp(ctx).edit().putLong(K_LAST_REPORT_AT, at).apply()

    fun lastError(ctx: Context) = sp(ctx).getString(K_LAST_ERROR, "") ?: ""
    fun setLastError(ctx: Context, msg: String) = sp(ctx).edit().putString(K_LAST_ERROR, msg).apply()

    fun backoffMs(ctx: Context) = sp(ctx).getLong(K_BACKOFF_MS, 0L)
    fun setBackoffMs(ctx: Context, ms: Long) = sp(ctx).edit().putLong(K_BACKOFF_MS, ms).apply()

    // ── VPN 守护 ──────────────────────────────────────────────────────────
    fun vpnDesired(ctx: Context) = sp(ctx).getBoolean(K_VPN_DESIRED, true)
    fun setVpnDesired(ctx: Context, desired: Boolean) =
        sp(ctx).edit().putBoolean(K_VPN_DESIRED, desired).apply()

    // ── 离线队列 ──────────────────────────────────────────────────────────
    fun queueJson(ctx: Context) = sp(ctx).getString(K_QUEUE, "[]") ?: "[]"
    fun setQueueJson(ctx: Context, json: String) = sp(ctx).edit().putString(K_QUEUE, json).apply()

    const val DEFAULT_INTERVAL_SEC = 1200
}
