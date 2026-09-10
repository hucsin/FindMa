package com.findma.elder

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class ElderApp : Application() {

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    /** 前台服务常驻通知渠道（DESIGN 7.2） */
    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notif_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notif_channel_desc)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "findma_guard"
    }
}
