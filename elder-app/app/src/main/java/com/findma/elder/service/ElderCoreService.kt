package com.findma.elder.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.findma.elder.BuildConfig
import com.findma.elder.ElderApp
import com.findma.elder.Prefs
import com.findma.elder.R
import com.findma.elder.config.ConfigSync
import com.findma.elder.location.LocationProvider
import com.findma.elder.model.ReportPoint
import com.findma.elder.model.ReportRequest
import com.findma.elder.net.ApiClient
import com.findma.elder.net.Battery
import com.findma.elder.net.NetState
import com.findma.elder.net.NetworkMonitor
import com.findma.elder.report.OfflineQueue
import com.findma.elder.report.ReportScheduler
import com.findma.elder.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex

/**
 * 常驻前台服务：调度 / 定位 / 上报的总入口（DESIGN 7.1 / 7.2）。
 *
 * 生命周期：
 *   onCreate  → 起前台通知 + 注册网络监听
 *   收到上报动作 → ensureRegistered → 取定位 → 入队 → 批量上报 → 应用配置 → 重设闹钟
 */
class ElderCoreService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cycleLock = Mutex()

    private lateinit var api: ApiClient
    private lateinit var location: LocationProvider
    private lateinit var queue: OfflineQueue
    private lateinit var monitor: NetworkMonitor

    override fun onCreate() {
        super.onCreate()
        api = ApiClient(this)
        location = LocationProvider(this)
        queue = OfflineQueue(this)
        monitor = NetworkMonitor(this)

        startForeground(NOTIF_ID, buildNotification("正在启动守护…"))

        monitor.start { state -> scope.launch { onNetworkChanged(state) } }
        Log.i(TAG, "service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                ReportScheduler.cancel(this)
                stopSelf()
                return START_NOT_STICKY
            }

            else -> scope.launch { runReportCycle() }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        monitor.stop()
        scope.cancel()
        Log.i(TAG, "service destroyed")
        super.onDestroy()
    }

    // ─────────────────────────────── 主循环 ────────────────────────────────

    private suspend fun runReportCycle() {
        // 防重入：闹钟与网络恢复可能同时触发
        if (!cycleLock.tryLock()) return
        try {
            if (!ensureRegistered()) {
                onReportFailed("设备注册失败")
                return
            }

            val mode = Prefs.mode(this)
            val intervalSec = Prefs.intervalSec(this)

            // ① 取定位（LOST 模式强制高精度 GPS）
            val fix = location.getLocation(
                highAccuracy = mode == MODE_LOST,
                maxAgeMs = intervalSec * 500L,
            )
            val battery = Battery.read(this)

            if (fix != null) {
                queue.push(
                    ReportPoint(
                        lat = fix.lat,
                        lng = fix.lng,
                        acc = fix.acc,
                        speed = null,
                        bearing = null,
                        batt = battery.level.takeIf { it in 0..100 },
                        charging = battery.charging,
                        provider = fix.provider,
                        devTs = System.currentTimeMillis(),
                    ),
                )
            }

            // ② 无网络 → 点位留在离线队列，等网络恢复补传（DESIGN 7.2）
            val net = monitor.current()
            val batch = queue.all()
            if (!net.online) {
                Log.i(TAG, "offline, ${batch.size} point(s) queued")
                updateNotification("离线中（已缓存 ${batch.size} 个点位）")
                ReportScheduler.schedule(this, intervalSec)
                return
            }
            if (batch.isEmpty()) {
                // 没有可用点位（定位失败且队列为空），仍按当前间隔继续调度
                ReportScheduler.schedule(this, intervalSec)
                return
            }

            // ③ 批量上报（含离线补传点）
            val res = api.report(
                token = Prefs.token(this),
                req = ReportRequest(
                    settingsVer = Prefs.settingsVer(this),
                    netType = net.kind(),
                    vpnActive = NetworkGuardVpnService.running,
                    appVer = BuildConfig.VERSION_NAME,
                    points = batch,
                ),
            )
            if (res == null) {
                onReportFailed("上报失败（保留 ${batch.size} 个点位待补传）")
                return
            }

            // ④ 成功后清空队列 + 应用服务端配置 + 按新间隔重设闹钟（DESIGN 5.2 / 9-①）
            queue.clear()
            Prefs.setLastReportAt(this, System.currentTimeMillis())
            Prefs.setLastError(this, "")
            Prefs.setBackoffMs(this, 0L)
            ConfigSync.apply(this, res.settings)

            ReportScheduler.schedule(this, res.settings.reportIntervalSec)
            updateNotification(
                "模式 ${res.settings.mode} · 每 ${res.settings.reportIntervalSec}s 上报 · " +
                    "本次 ${res.accepted} 点",
            )
            Log.i(TAG, "report ok: accepted=${res.accepted} rejected=${res.rejected} mode=${res.settings.mode}")
        } catch (t: Throwable) {
            Log.e(TAG, "report cycle error", t)
            onReportFailed(t.message ?: "未知错误")
        } finally {
            cycleLock.unlock()
        }
    }

    /** 首次启动注册，拿到 deviceId / token / bindCode（DESIGN 5.4） */
    private suspend fun ensureRegistered(): Boolean {
        if (Prefs.token(this).isNotBlank()) return true
        val reg = api.register() ?: return false
        Prefs.saveIdentity(this, reg.deviceId, reg.token, reg.bindCode)
        Log.i(TAG, "registered device=${reg.deviceId} bindCode=${reg.bindCode}")
        return true
    }

    /** 失败退避：+2 分钟起，翻倍，上限 15 分钟（DESIGN 7.2） */
    private fun onReportFailed(message: String) {
        Prefs.setLastError(this, message)
        val current = Prefs.backoffMs(this)
        val next = if (current <= 0L) 2 * 60_000L else (current * 2).coerceAtMost(MAX_BACKOFF_MS)
        Prefs.setBackoffMs(this, next)
        ReportScheduler.schedule(this, (next / 1000L).toInt())
        updateNotification("上报异常：$message")
    }

    /** 网络变化：WiFi 关守护、蜂窝开守护；网络恢复立即补传（DESIGN 7.3 / 9-④） */
    private suspend fun onNetworkChanged(state: NetState) {
        Log.i(TAG, "network: wifi=${state.wifi} cellular=${state.cellular} online=${state.online}")

        if (state.wifi) {
            NetworkGuardVpnService.stop(this)
        } else if (state.cellular && Prefs.vpnDesired(this)) {
            NetworkGuardVpnService.start(this)
        }

        if (state.online && queue.all().isNotEmpty()) {
            runReportCycle()
        }
    }

    // ─────────────────────────────── 通知 ──────────────────────────────────

    private fun buildNotification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            pendingFlags(),
        )

        return NotificationCompat.Builder(this, ElderApp.CHANNEL_ID)
            .setContentTitle(getString(R.string.notif_title))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_findma)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun updateNotification(text: String) {
        runCatching {
            val nm = ContextCompat.getSystemService(this, android.app.NotificationManager::class.java)
            nm?.notify(NOTIF_ID, buildNotification(text))
        }
    }

    private fun pendingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    companion object {
        private const val TAG = "FindMaCore"
        private const val NOTIF_ID = 1001
        private const val MAX_BACKOFF_MS = 15 * 60_000L
        private const val MODE_LOST = "LOST"

        const val ACTION_START = "com.findma.elder.action.START"
        const val ACTION_REPORT_NOW = "com.findma.elder.action.REPORT_NOW"
        const val ACTION_STOP = "com.findma.elder.action.STOP"

        fun start(ctx: Context) = send(ctx, ACTION_START)
        fun reportNow(ctx: Context) = send(ctx, ACTION_REPORT_NOW)
        fun stop(ctx: Context) = send(ctx, ACTION_STOP)

        private fun send(ctx: Context, action: String) {
            runCatching {
                ContextCompat.startForegroundService(
                    ctx,
                    Intent(ctx, ElderCoreService::class.java).setAction(action),
                )
            }.onFailure { Log.w(TAG, "startForegroundService($action) failed", it) }
        }
    }
}
