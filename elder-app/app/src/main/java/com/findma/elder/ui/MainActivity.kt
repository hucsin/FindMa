package com.findma.elder.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.findma.elder.Prefs
import com.findma.elder.R
import com.findma.elder.net.Battery
import com.findma.elder.net.NetworkMonitor
import com.findma.elder.report.OfflineQueue
import com.findma.elder.service.ElderCoreService
import com.findma.elder.service.NetworkGuardVpnService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 状态页（DESIGN 7.5）：运行状态、VPN 状态、定位/网络/电量、下次上报倒计时、
 * 绑定二维码 + 明文绑定码 + 重置入口、保活引导、电池白名单申请。
 * 主界面无多余操作，防误触。
 */
class MainActivity : AppCompatActivity() {

    private lateinit var tvStatus: TextView
    private lateinit var tvInfo: TextView
    private lateinit var tvBindCode: TextView
    private lateinit var ivQr: ImageView

    private val queue by lazy { OfflineQueue(this) }
    private val monitor by lazy { NetworkMonitor(this) }

    private val vpnConsentLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == RESULT_OK) {
                NetworkGuardVpnService.start(this)
                toast("网络守护已授权")
            } else {
                toast("未授权，蜂窝网络下其他 App 仍可联网")
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        tvStatus = findViewById(R.id.tvStatus)
        tvInfo = findViewById(R.id.tvInfo)
        tvBindCode = findViewById(R.id.tvBindCode)
        ivQr = findViewById(R.id.ivQr)

        findViewById<Button>(R.id.btnStart).setOnClickListener {
            ElderCoreService.start(this)
            toast("守护已启动")
        }

        findViewById<Button>(R.id.btnReportNow).setOnClickListener {
            ElderCoreService.reportNow(this)
            toast("已触发一次上报")
        }

        findViewById<Button>(R.id.btnVpn).setOnClickListener { requestVpnConsent() }

        findViewById<Button>(R.id.btnBattery).setOnClickListener { requestIgnoreBatteryOptimization() }

        findViewById<Button>(R.id.btnKeepAlive).setOnClickListener {
            startActivity(Intent(this, KeepAliveActivity::class.java))
        }

        // 重置绑定码需长按确认（防误触）
        findViewById<Button>(R.id.btnResetCode).setOnClickListener {
            toast("重置绑定码请长按（防误触）")
        }
        findViewById<Button>(R.id.btnResetCode).setOnLongClickListener {
            resetBindCode()
            true
        }

        requestRuntimePermissions()
        ElderCoreService.start(this)
        renderBindCode()
    }

    override fun onResume() {
        super.onResume()
        renderBindCode()
        lifecycleScope.launch {
            while (isActive) {
                refreshStatus()
                delay(1000)
            }
        }
    }

    // ─────────────────────────────── 状态刷新 ──────────────────────────────

    private suspend fun refreshStatus() {
        val mode = Prefs.mode(this)
        val intervalSec = Prefs.intervalSec(this)
        val nextAt = Prefs.nextReportAt(this)
        val lastAt = Prefs.lastReportAt(this)
        val error = Prefs.lastError(this)
        val queued = queue.all().size
        val battery = Battery.read(this)
        val net = monitor.current()
        val running = NetworkGuardVpnService.running

        val countdown = when {
            nextAt <= 0L -> "未调度"
            nextAt <= System.currentTimeMillis() -> "即将上报"
            else -> "${(nextAt - System.currentTimeMillis()) / 1000} 秒后"
        }

        tvStatus.text = buildString {
            append("守护模式：").append(modeName(mode)).append('\n')
            append("上报间隔：").append(intervalSec).append(" 秒\n")
            append("下次上报：").append(countdown).append('\n')
            append("最后成功：").append(if (lastAt > 0) fmtTime(lastAt) else "尚未上报")
        }

        tvInfo.text = buildString {
            append("网络：").append(net.kind()).append(if (net.online) "（在线）" else "（离线）").append('\n')
            append("流量守护：").append(if (running) "已生效" else "未运行").append('\n')
            append("电量：").append(if (battery.level >= 0) "${battery.level}%" else "未知")
            append(if (battery.charging) "（充电中）" else "").append('\n')
            append("待补传点位：").append(queued).append(" 个")
            if (error.isNotBlank()) append('\n').append("最近异常：").append(error)
        }
    }

    private fun renderBindCode() {
        val code = Prefs.bindCode(this)
        if (code.isBlank()) {
            tvBindCode.text = "——"
            ivQr.setImageBitmap(null)
            return
        }
        tvBindCode.text = code
        val sizePx = (240 * resources.displayMetrics.density).toInt()
        lifecycleScope.launch {
            val bitmap = withContext(Dispatchers.Default) {
                QrUtil.render("${QrUtil.BIND_PREFIX}$code", sizePx)
            }
            ivQr.setImageBitmap(bitmap)
        }
    }

    // ─────────────────────────────── 交互 ─────────────────────────────────

    private fun resetBindCode() {
        val token = Prefs.token(this)
        if (token.isBlank()) {
            toast("设备尚未注册，请先启动守护")
            return
        }
        lifecycleScope.launch {
            val code = com.findma.elder.net.ApiClient(this@MainActivity).rebindCode(token)
            if (code == null) {
                toast("重置失败，请检查网络")
                return@launch
            }
            Prefs.saveBindCode(this@MainActivity, code)
            renderBindCode()
            toast("绑定码已重置，旧二维码已作废")
        }
    }

    private fun requestVpnConsent() {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            NetworkGuardVpnService.start(this)
            toast("网络守护已开启")
        } else {
            vpnConsentLauncher.launch(intent)
        }
    }

    private fun requestIgnoreBatteryOptimization() {
        val pm = getSystemService(PowerManager::class.java)
        if (pm != null && pm.isIgnoringBatteryOptimizations(packageName)) {
            toast("已在电池优化白名单中")
            return
        }
        runCatching {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
            )
        }.onFailure {
            runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
        }
    }

    private fun requestRuntimePermissions() {
        val wanted = mutableListOf<String>()
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) {
            wanted += Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (!granted(Manifest.permission.ACCESS_COARSE_LOCATION)) {
            wanted += Manifest.permission.ACCESS_COARSE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !granted(Manifest.permission.POST_NOTIFICATIONS)
        ) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
        }
        if (wanted.isNotEmpty()) requestPermissions(wanted.toTypedArray(), REQ_BASE)

        // 精确定时（Android 12+ 需用户显式授权，否则降级为 WorkManager 兜底）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val am = getSystemService(android.app.AlarmManager::class.java)
            if (am != null && !am.canScheduleExactAlarms()) {
                runCatching {
                    startActivity(
                        Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        // 后台定位必须在前台定位授予之后单独申请（系统要求）
        if (requestCode == REQ_BASE &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            granted(Manifest.permission.ACCESS_FINE_LOCATION) &&
            !granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        ) {
            requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQ_BACKGROUND)
        }
    }

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun modeName(mode: String) = when (mode) {
        "LOST" -> "丢失（高频定位）"
        "WATCH" -> "关注（围栏提醒）"
        else -> "普通"
    }

    private fun fmtTime(ts: Long): String {
        val sdf = java.text.SimpleDateFormat("MM-dd HH:mm:ss", java.util.Locale.getDefault())
        return sdf.format(java.util.Date(ts))
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    companion object {
        private const val REQ_BASE = 1001
        private const val REQ_BACKGROUND = 1002
    }
}
