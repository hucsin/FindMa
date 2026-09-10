package com.findma.elder.service

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import com.findma.elder.Prefs
import java.io.FileInputStream

/**
 * VPN 网络守护（DESIGN 7.3 / 9-④）：
 *
 *  ┌ WiFi 已连接 → 停止 VPN，所有 App 正常联网
 *  └ WiFi 断开（蜂窝）→ 建立 tun，接管 0.0.0.0/0，但**不转发任何数据包**
 *                        → 除本 App 外的联网请求全部失败（等于直接拒绝）
 *                        → 本 App 通过 addDisallowedApplication 排除在 VPN 之外，正常上报
 *
 * 注意：Android 同时只允许一个 VPN；若被第三方 VPN 抢占，本服务会收到 onRevoke，
 *       此时 vpnActive=false 会随上报回传，子女端收到 GUARD_OFF 告警。
 */
class NetworkGuardVpnService : VpnService() {

    private var tun: ParcelFileDescriptor? = null
    private var drainThread: Thread? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutdown()
                stopSelf()
                return START_NOT_STICKY
            }

            else -> startGuard()
        }
        return START_STICKY
    }

    private fun startGuard() {
        if (tun != null) return

        val builder = Builder()
            .setSession("FindMa 网络守护")
            .addAddress(VPN_ADDRESS, VPN_PREFIX)
            .addRoute("0.0.0.0", 0)
            .setBlocking(false)

        // 本 App 排除在 VPN 之外，走蜂窝网络正常上报
        runCatching { builder.addDisallowedApplication(packageName) }
            .onFailure { Log.w(TAG, "addDisallowedApplication failed", it) }

        val descriptor = runCatching { builder.establish() }.getOrNull()
        if (descriptor == null) {
            Log.w(TAG, "establish() returned null（未授权或被其他 VPN 占用）")
            running = false
            return
        }

        tun = descriptor
        running = true
        Prefs.setVpnDesired(this, true)
        Log.i(TAG, "guard started")

        // 后台持续读取并丢弃数据包，防止 tun 缓冲堆积（CPU 占用极低）
        drainThread = Thread({ drain(descriptor) }, "findma-vpn-drain").also { it.start() }
    }

    private fun drain(descriptor: ParcelFileDescriptor) {
        val buffer = ByteArray(32767)
        try {
            FileInputStream(descriptor.fileDescriptor).use { input ->
                while (!Thread.currentThread().isInterrupted) {
                    if (input.read(buffer) < 0) break
                    // 刻意不转发：所有包在此丢弃
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "drain ended", t)
        } finally {
            releaseTun()
        }
    }

    /** 被第三方 VPN 顶掉 / 用户撤销授权时回调 */
    override fun onRevoke() {
        Log.w(TAG, "onRevoke: VPN 授权被撤销或被其他 VPN 占用")
        shutdown()
        super.onRevoke()
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        drainThread?.interrupt()
        drainThread = null
        releaseTun()
        Log.i(TAG, "guard stopped")
    }

    private fun releaseTun() {
        runCatching { tun?.close() }
        tun = null
        running = false
    }

    companion object {
        private const val TAG = "FindMaVpn"
        private const val VPN_ADDRESS = "10.111.0.1"
        private const val VPN_PREFIX = 24

        const val ACTION_START = "com.findma.elder.vpn.START"
        const val ACTION_STOP = "com.findma.elder.vpn.STOP"

        /** 当前守护是否运行；随上报回传 vpnActive（DESIGN 6.5 GUARD_OFF） */
        @Volatile
        var running: Boolean = false
            private set

        /** 启动守护；未授权时直接返回（授权入口在状态页，DESIGN 7.3 边界处理） */
        fun start(ctx: Context) {
            if (VpnService.prepare(ctx) != null) {
                Log.w(TAG, "VPN 尚未授权，需用户在状态页点击授权")
                return
            }
            send(ctx, ACTION_START)
        }

        fun stop(ctx: Context) {
            Prefs.setVpnDesired(ctx, false)
            send(ctx, ACTION_STOP)
        }

        private fun send(ctx: Context, action: String) {
            runCatching { ctx.startService(Intent(ctx, NetworkGuardVpnService::class.java).setAction(action)) }
                .onFailure { Log.w(TAG, "startService($action) failed", it) }
        }
    }
}
