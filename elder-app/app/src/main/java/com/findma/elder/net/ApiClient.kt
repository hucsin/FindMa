package com.findma.elder.net

import android.content.Context
import android.os.Build
import android.util.Log
import com.findma.elder.BuildConfig
import com.findma.elder.model.RegisterResult
import com.findma.elder.model.ReportPoint
import com.findma.elder.model.ReportRequest
import com.findma.elder.model.ReportResponse
import com.findma.elder.model.ServerSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * HTTPS 上报客户端（DESIGN 7.1，OkHttp）。
 * 全部 JSON 手工拼装，避免引入额外序列化依赖。
 */
class ApiClient(@Suppress("UNUSED_PARAMETER") ctx: Context) {

    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    /** POST /device/register —— 首次启动注册，拿到 deviceId / token / bindCode */
    suspend fun register(): RegisterResult? = withContext(Dispatchers.IO) {
        val payload = JSONObject()
            .put("name", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
            .toString()

        val req = Request.Builder()
            .url("${BuildConfig.API_BASE}/device/register")
            .header("User-Agent", BuildConfig.APP_USER_AGENT)
            .post(payload.toRequestBody(JSON))
            .build()

        runCatching {
            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    Log.w(TAG, "register failed ${resp.code}: $text")
                    return@use null
                }
                val j = JSONObject(text)
                RegisterResult(
                    deviceId = j.getString("deviceId"),
                    token = j.getString("token"),
                    bindCode = j.getString("bindCode"),
                )
            }
        }.getOrElse {
            Log.w(TAG, "register error", it)
            null
        }
    }

    /** POST /device/rebind-code —— 重置绑定码（旧码立即作废） */
    suspend fun rebindCode(token: String): String? = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url("${BuildConfig.API_BASE}/device/rebind-code")
            .header("X-Device-Token", token)
            .header("User-Agent", BuildConfig.APP_USER_AGENT)
            .post(EMPTY.toRequestBody(JSON))
            .build()

        runCatching {
            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    Log.w(TAG, "rebind failed ${resp.code}: $text")
                    return@use null
                }
                JSONObject(text).getString("bindCode")
            }
        }.getOrElse {
            Log.w(TAG, "rebind error", it)
            null
        }
    }

    /** POST /report —— 上报位置（含离线补传），响应携带最新配置 */
    suspend fun report(token: String, req: ReportRequest): ReportResponse? = withContext(Dispatchers.IO) {
        val points = JSONArray()
        for (p in req.points) points.put(pointToJson(p))

        val payload = JSONObject()
            .put("settingsVer", req.settingsVer)
            .put("netType", req.netType)
            .put("vpnActive", req.vpnActive)
            .put("appVer", req.appVer)
            .put("points", points)
            .toString()

        val httpReq = Request.Builder()
            .url("${BuildConfig.API_BASE}/report")
            .header("X-Device-Token", token)
            .header("User-Agent", BuildConfig.APP_USER_AGENT)
            .post(payload.toRequestBody(JSON))
            .build()

        runCatching {
            http.newCall(httpReq).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    Log.w(TAG, "report failed ${resp.code}: $text")
                    return@use null
                }
                val j = JSONObject(text)
                val s = j.getJSONObject("settings")
                ReportResponse(
                    serverTs = j.optLong("serverTs", System.currentTimeMillis()),
                    settings = ServerSettings(
                        ver = s.optInt("ver", 1),
                        mode = s.optString("mode", "NORMAL"),
                        reportIntervalSec = s.optInt("reportIntervalSec", 1200),
                        normalIntervalSec = s.optInt("normalIntervalSec", 1200),
                        lostIntervalSec = s.optInt("lostIntervalSec", 60),
                        fenceEnabled = s.optBoolean("fenceEnabled", true),
                    ),
                    accepted = j.optInt("accepted", req.points.size),
                    rejected = j.optInt("rejected", 0),
                )
            }
        }.getOrElse {
            Log.w(TAG, "report error", it)
            null
        }
    }

    private fun pointToJson(p: ReportPoint): JSONObject = JSONObject().apply {
        put("lat", p.lat)
        put("lng", p.lng)
        p.acc?.let { put("acc", it.toDouble()) }
        p.speed?.let { put("speed", it.toDouble()) }
        p.bearing?.let { put("bearing", it.toDouble()) }
        p.batt?.let { put("batt", it) }
        put("charging", p.charging)
        put("provider", p.provider)
        put("devTs", p.devTs)
    }

    companion object {
        private const val TAG = "FindMaApi"
        private val JSON = "application/json; charset=utf-8".toMediaType()
        private const val EMPTY = "{}"
    }
}
