package com.findma.elder.report

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.findma.elder.service.ElderCoreService

/** 精确闹钟到点 → 触发一次上报（DESIGN 5.3 / 9-①） */
class ReportAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ALARM) return
        ContextCompat.startForegroundService(
            context,
            Intent(context, ElderCoreService::class.java).setAction(ElderCoreService.ACTION_REPORT_NOW),
        )
    }

    companion object {
        const val ACTION_ALARM = "com.findma.elder.action.ALARM_REPORT"
    }
}
