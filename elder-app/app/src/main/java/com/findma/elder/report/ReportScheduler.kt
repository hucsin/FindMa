package com.findma.elder.report

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.findma.elder.Prefs
import java.util.concurrent.TimeUnit

/**
 * 上报调度（DESIGN 5.3）：
 *  主路径：AlarmManager.setExactAndAllowWhileIdle（Doze 下也能触发）；
 *  降级：SCHEDULE_EXACT_ALARM 被拒 → setAndAllowWhileIdle + WorkManager(15min) 兜底。
 * 每次上报成功后按 Worker 下发的新间隔重设下一次闹钟。
 */
object ReportScheduler {

    private const val REQ_CODE = 1001
    private const val WORK_NAME = "findma_fallback_report"

    fun schedule(ctx: Context, intervalSec: Int) {
        val safeInterval = intervalSec.coerceAtLeast(MIN_INTERVAL_SEC)
        val at = System.currentTimeMillis() + safeInterval * 1000L
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val exact = canScheduleExact(am)
        runCatching {
            if (exact) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(ctx))
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(ctx))
            }
        }.onFailure {
            Log.w(TAG, "setAlarm failed, fallback to inexact", it)
            runCatching { am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(ctx)) }
        }

        Prefs.setNextReportAt(ctx, at)

        // 精确闹钟不可用时，额外挂一个 WorkManager 周期任务兜底（系统会在 Doze 下批量放行）
        if (!exact) ensureFallbackWorker(ctx)
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        runCatching { am.cancel(pendingIntent(ctx)) }
        Prefs.setNextReportAt(ctx, 0L)
    }

    private fun canScheduleExact(am: AlarmManager): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true

    private fun ensureFallbackWorker(ctx: Context) {
        runCatching {
            val request = PeriodicWorkRequestBuilder<ReportWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(ctx)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }.onFailure { Log.w(TAG, "enqueue fallback worker failed", it) }
    }

    private fun pendingIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, ReportAlarmReceiver::class.java)
            .setAction(ReportAlarmReceiver.ACTION_ALARM)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, REQ_CODE, intent, flags)
    }

    private const val TAG = "FindMaSched"
    private const val MIN_INTERVAL_SEC = 15
}
