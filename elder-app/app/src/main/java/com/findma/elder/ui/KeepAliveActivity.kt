package com.findma.elder.ui

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.findma.elder.R

/**
 * 保活设置引导页（DESIGN 7.6 / 425）。
 *
 * 国产 ROM 的后台清理无法用代码根治，业界通行做法是
 * 「前台服务 + 精确闹钟 + 引导用户手工放行」三管齐下。
 * 本页按品牌给出「自启动 / 后台无限制 / 电池白名单」的直达入口；
 * 任何一步跳转失败都降级到系统应用详情页，避免按钮点了没反应。
 */
class KeepAliveActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_keepalive)

        findViewById<TextView>(R.id.tvBrand).text =
            getString(R.string.keepalive_brand_fmt, brandDisplay())
        findViewById<TextView>(R.id.tvSteps).text = stepsText()

        findViewById<Button>(R.id.btnAutostart).setOnClickListener { openAutostart() }
        findViewById<Button>(R.id.btnBatteryOpt).setOnClickListener { openBatterySettings() }
        findViewById<Button>(R.id.btnAppInfo).setOnClickListener { openAppInfo() }
        findViewById<Button>(R.id.btnDone).setOnClickListener { finish() }
    }

    // ────────────────────────────────────────────────────────────────────
    // 品牌识别
    // ────────────────────────────────────────────────────────────────────

    private fun brandKey(): String {
        val s = "${Build.MANUFACTURER} ${Build.BRAND}".lowercase()
        return when {
            s.contains("xiaomi") || s.contains("redmi") || s.contains("poco") -> "xiaomi"
            s.contains("huawei") || s.contains("honor") -> "huawei"
            s.contains("oppo") || s.contains("realme") || s.contains("oneplus") -> "oppo"
            s.contains("vivo") || s.contains("iqoo") -> "vivo"
            s.contains("samsung") -> "samsung"
            s.contains("meizu") -> "meizu"
            else -> "other"
        }
    }

    private fun brandDisplay(): String = when (brandKey()) {
        "xiaomi" -> "小米 / Redmi / POCO"
        "huawei" -> "华为 / 荣耀"
        "oppo" -> "OPPO / 一加 / realme"
        "vivo" -> "vivo / iQOO"
        "samsung" -> "三星"
        "meizu" -> "魅族"
        else -> "${Build.MANUFACTURER}（通用引导）"
    }

    private fun stepsText(): String = when (brandKey()) {
        "xiaomi" ->
            "① 自启动：设置 → 应用设置 → 应用管理 → 本应用 → 自启动，打开\n" +
                "② 省电策略：设置 → 省电与电池 → 应用智能省电 → 本应用 → 无限制\n" +
                "③ 后台加锁：最近任务列表下拉本应用卡片加锁，避免一键清理"
        "huawei" ->
            "① 自启动：设置 → 应用 → 应用启动管理 → 本应用 → 手动管理，三项全开\n" +
                "② 电池优化：设置 → 电池 → 更多电池设置，关闭对本应用的后台限制\n" +
                "③ 后台加锁：最近任务列表下拉本应用卡片加锁"
        "oppo" ->
            "① 自启动：设置 → 应用管理 → 本应用 → 允许自启动 / 允许后台活动，全部打开\n" +
                "② 省电策略：设置 → 电池 → 更多设置 → 睡眠待机优化，关闭\n" +
                "③ 后台加锁：最近任务列表下拉本应用卡片加锁"
        "vivo" ->
            "① 自启动：设置 → 应用与权限 → 权限管理 → 自启动，打开本应用\n" +
                "② 后台高耗电：设置 → 电池 → 后台高耗电，允许本应用\n" +
                "③ 后台加锁：最近任务列表下拉本应用卡片加锁"
        "samsung" ->
            "① 后台限制：设置 → 电池和设备维护 → 电池 → 后台使用限制，" +
                "把本应用加入「不休眠的应用」\n" +
                "② 关闭「自适应电池」对本应用的限制"
        "meizu" ->
            "① 自启动：手机管家 → 权限管理 → 自启动管理，打开本应用\n" +
                "② 后台：设置 → 电量管理 → 后台管理，允许本应用后台运行"
        else ->
            "① 自启动：在系统设置里搜索「自启动」，把本应用加白\n" +
                "② 电池优化：把本应用从电池优化名单中排除\n" +
                "③ 后台加锁：最近任务列表下拉本应用卡片加锁"
    }

    /** 各品牌「自启动管理」页面的候选组件；按顺序尝试，全失败则降级到应用详情页 */
    private fun autostartCandidates(): List<ComponentName> = when (brandKey()) {
        "xiaomi" -> listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
        )
        "huawei" -> listOf(
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity",
            ),
        )
        "oppo" -> listOf(
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity",
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity",
            ),
        )
        "vivo" -> listOf(
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            ),
            ComponentName(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            ),
        )
        "samsung" -> listOf(
            ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity",
            ),
        )
        else -> emptyList()
    }

    // ────────────────────────────────────────────────────────────────────
    // 跳转
    // ────────────────────────────────────────────────────────────────────

    private fun openAutostart() {
        for (cn in autostartCandidates()) {
            if (tryStart(Intent().setComponent(cn))) return
        }
        toast("未能直达自启动页面，请在应用详情页中手动查找")
        openAppInfo()
    }

    private fun openBatterySettings() {
        if (tryStart(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) return
        toast("未能打开电池优化设置，请手动查找")
        openAppInfo()
    }

    private fun openAppInfo() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))
        if (!tryStart(intent)) toast("未能打开应用详情页，请到系统设置中查找本应用")
    }

    /** 组件不存在或被 ROM 拦截时返回 false，交由调用方降级 */
    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun toast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    }
}
