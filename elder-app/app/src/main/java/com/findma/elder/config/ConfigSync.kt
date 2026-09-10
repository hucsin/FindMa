package com.findma.elder.config

import android.content.Context
import com.findma.elder.Prefs
import com.findma.elder.model.ServerSettings

/**
 * 服务端配置应用（DESIGN 5.2 / 7.1）。
 * 幂等：每次上报响应都携带"当前生效值"，本地直接覆盖写入即可。
 */
object ConfigSync {

    /**
     * 应用配置并返回是否发生变化。
     * 变化时调用方应立即在 Worker 已下发的新间隔上重设下次闹钟。
     */
    fun apply(ctx: Context, s: ServerSettings): Boolean {
        val changed = Prefs.settingsVer(ctx) != s.ver ||
            Prefs.mode(ctx) != s.mode ||
            Prefs.intervalSec(ctx) != s.reportIntervalSec

        Prefs.saveSettings(
            ctx = ctx,
            ver = s.ver,
            mode = s.mode,
            intervalSec = s.reportIntervalSec.coerceAtLeast(MIN_INTERVAL_SEC),
            normalIntervalSec = s.normalIntervalSec,
            lostIntervalSec = s.lostIntervalSec,
            fenceEnabled = s.fenceEnabled,
        )
        return changed
    }

    private const val MIN_INTERVAL_SEC = 15
}
