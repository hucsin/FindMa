package com.findma.elder.report

import android.content.Context
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.findma.elder.service.ElderCoreService

/**
 * 精确闹钟不可用时的兜底（DESIGN 5.3）：
 * WorkManager 每 15 分钟唤醒一次，触发与闹钟相同的上报动作。
 */
class ReportWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    override fun doWork(): Result {
        ContextCompat.startForegroundService(
            applicationContext,
            android.content.Intent(applicationContext, ElderCoreService::class.java)
                .setAction(ElderCoreService.ACTION_REPORT_NOW),
        )
        return Result.success()
    }
}
