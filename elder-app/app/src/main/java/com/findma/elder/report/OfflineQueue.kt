package com.findma.elder.report

import android.content.Context
import android.util.Log
import com.findma.elder.Prefs
import com.findma.elder.model.ReportPoint
import org.json.JSONArray
import org.json.JSONObject

/**
 * 离线队列（DESIGN 7.2）：本地最多缓存 50 个点，网络恢复后随下次上报批量补传。
 * 采用"快照 + 成功才清空"语义：上报失败时点位不丢。
 */
class OfflineQueue(private val ctx: Context) {

    /** 读取全部待传点（不移除） */
    fun all(): List<ReportPoint> {
        val json = Prefs.queueJson(ctx)
        return runCatching {
            val arr = JSONArray(json)
            (0 until arr.length()).map { arr.getJSONObject(it).toPoint() }
        }.getOrElse {
            Log.w(TAG, "parse queue failed", it)
            emptyList()
        }
    }

    /** 追加一个点；超过上限时丢弃最旧的点 */
    fun push(point: ReportPoint) {
        val list = all().toMutableList()
        list.add(point)
        while (list.size > MAX) list.removeAt(0)
        save(list)
    }

    fun clear() = save(emptyList())

    private fun save(list: List<ReportPoint>) {
        val arr = JSONArray()
        for (p in list) arr.put(p.toJson())
        Prefs.setQueueJson(ctx, arr.toString())
    }

    private fun ReportPoint.toJson(): JSONObject = JSONObject().apply {
        put("lat", lat)
        put("lng", lng)
        acc?.let { put("acc", it.toDouble()) }
        speed?.let { put("speed", it.toDouble()) }
        bearing?.let { put("bearing", it.toDouble()) }
        batt?.let { put("batt", it) }
        put("charging", charging)
        put("provider", provider)
        put("devTs", devTs)
    }

    private fun JSONObject.toPoint(): ReportPoint = ReportPoint(
        lat = getDouble("lat"),
        lng = getDouble("lng"),
        acc = if (has("acc")) getDouble("acc").toFloat() else null,
        speed = if (has("speed")) getDouble("speed").toFloat() else null,
        bearing = if (has("bearing")) getDouble("bearing").toFloat() else null,
        batt = if (has("batt")) getInt("batt") else null,
        charging = optBoolean("charging", false),
        provider = optString("provider", "unknown"),
        devTs = optLong("devTs", System.currentTimeMillis()),
    )

    companion object {
        private const val TAG = "FindMaQueue"
        private const val MAX = 50
    }
}
