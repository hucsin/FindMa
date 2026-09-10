package com.findma.elder.model

/** 老人端上报的单点（对应 Worker /report 的 points[]） */
data class ReportPoint(
    val lat: Double,
    val lng: Double,
    val acc: Float?,
    val speed: Float?,
    val bearing: Float?,
    val batt: Int?,
    val charging: Boolean,
    val provider: String,
    val devTs: Long,
)

/** 一次上报请求体 */
data class ReportRequest(
    val settingsVer: Int,
    val netType: String,
    val vpnActive: Boolean,
    val appVer: String,
    val points: List<ReportPoint>,
)

/** 服务端下发的生效配置（DESIGN 6.2 响应体） */
data class ServerSettings(
    val ver: Int,
    val mode: String,
    val reportIntervalSec: Int,
    val normalIntervalSec: Int,
    val lostIntervalSec: Int,
    val fenceEnabled: Boolean,
)

data class ReportResponse(
    val serverTs: Long,
    val settings: ServerSettings,
    val accepted: Int,
    val rejected: Int,
)

/** 首次注册返回（DESIGN 5.4） */
data class RegisterResult(
    val deviceId: String,
    val token: String,
    val bindCode: String,
)
