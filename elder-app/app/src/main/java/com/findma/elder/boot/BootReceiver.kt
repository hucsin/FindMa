package com.findma.elder.boot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.findma.elder.Prefs
import com.findma.elder.service.ElderCoreService

/**
 * 开机 / 应用更新后恢复调度与 VPN 状态（DESIGN 5.3 / 7.3 边界处理）。
 * 只有已注册（有 token）的设备才自启，避免首次安装就弹前台服务。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> {
                if (Prefs.token(context).isBlank()) return
                Log.i(TAG, "boot event ${intent.action}, restarting guard")
                ElderCoreService.start(context)
            }
        }
    }

    companion object {
        private const val TAG = "FindMaBoot"
    }
}
