package com.findma.elder.net

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

/** 电量 / 充电状态读取（用于上报与低电告警，DESIGN 6.5） */
object Battery {

    data class State(val level: Int, val charging: Boolean)

    fun read(ctx: Context): State {
        val intent: Intent? = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent == null) return State(-1, false)

        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)

        val pct = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL

        return State(pct, charging)
    }
}
