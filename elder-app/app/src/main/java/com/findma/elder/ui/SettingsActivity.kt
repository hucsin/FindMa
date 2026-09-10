package com.findma.elder.ui

import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.findma.elder.BuildConfig
import com.findma.elder.R
import com.findma.elder.update.UpdateManager
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 设置页：目前承载「软件更新」。
 *
 * 更新流程（按需求）：
 *   点按钮 → 先检查「安装未知应用」权限
 *     ├─ 没有 → 跳系统设置授权页，回来后自动续跑
 *     └─ 有   → 从 https://dl.izao.cc/elder.apk 流式下载
 *                 按钮下方实时显示进度 → 下载完成拉起系统安装器
 */
class SettingsActivity : AppCompatActivity() {

    private lateinit var tvVersion: TextView
    private lateinit var tvPerm: TextView
    private lateinit var tvProgress: TextView
    private lateinit var tvSource: TextView
    private lateinit var btnUpdate: Button
    private lateinit var pbUpdate: ProgressBar

    private var downloadJob: Job? = null
    private var downloading = false

    /** 因为缺权限而跳去了系统设置，回来后要自动接着下载 */
    private var awaitingPermission = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        tvVersion = findViewById(R.id.tvVersion)
        tvPerm = findViewById(R.id.tvPerm)
        tvProgress = findViewById(R.id.tvProgress)
        tvSource = findViewById(R.id.tvSource)
        btnUpdate = findViewById(R.id.btnUpdate)
        pbUpdate = findViewById(R.id.pbUpdate)

        tvVersion.text = getString(
            R.string.settings_version_fmt,
            BuildConfig.VERSION_NAME,
            BuildConfig.VERSION_CODE,
        )
        tvSource.text = getString(R.string.settings_update_source_fmt, BuildConfig.UPDATE_URL)

        btnUpdate.setOnClickListener { onUpdateClicked() }
        renderPermissionState()
    }

    override fun onResume() {
        super.onResume()
        renderPermissionState()

        if (awaitingPermission) {
            awaitingPermission = false
            if (UpdateManager.canInstall(this)) {
                toast(getString(R.string.update_perm_granted_toast))
                beginDownload()
            } else {
                toast(getString(R.string.update_perm_denied_toast))
            }
        }
    }

    override fun onDestroy() {
        downloadJob?.cancel()
        super.onDestroy()
    }

    // ─────────────────────────────── 交互 ─────────────────────────────────

    private fun onUpdateClicked() {
        if (downloading) {
            toast(getString(R.string.update_busy_toast))
            return
        }
        if (!UpdateManager.canInstall(this)) {
            awaitingPermission = true
            toast(getString(R.string.update_perm_toast))
            if (!UpdateManager.openInstallPermissionSettings(this)) {
                awaitingPermission = false
                toast(getString(R.string.update_perm_no_page_toast))
            }
            return
        }
        beginDownload()
    }

    private fun beginDownload() {
        if (downloading) return
        downloading = true
        btnUpdate.isEnabled = false
        pbUpdate.visibility = View.VISIBLE
        pbUpdate.isIndeterminate = true
        tvProgress.visibility = View.VISIBLE
        tvProgress.text = getString(R.string.update_connecting)

        downloadJob = lifecycleScope.launch {
            try {
                val apk = UpdateManager.download(this@SettingsActivity) { p ->
                    runOnUiThread { renderProgress(p) }
                }
                tvProgress.text = getString(R.string.update_installing)
                UpdateManager.install(this@SettingsActivity, apk)
                toast(getString(R.string.update_done_toast))
            } catch (e: Exception) {
                tvProgress.text = getString(
                    R.string.update_failed_fmt,
                    e.message ?: e.javaClass.simpleName,
                )
                toast(getString(R.string.update_error_toast))
            } finally {
                downloading = false
                btnUpdate.isEnabled = true
                pbUpdate.isIndeterminate = false
            }
        }
    }

    // ─────────────────────────────── 渲染 ─────────────────────────────────

    private fun renderPermissionState() {
        val ok = UpdateManager.canInstall(this)
        tvPerm.text = getString(
            if (ok) R.string.settings_perm_ready else R.string.settings_perm_needed,
        )
        tvPerm.setTextColor(ContextCompat.getColor(this, if (ok) R.color.ok else R.color.warn))
    }

    private fun renderProgress(p: UpdateManager.Progress) {
        if (p.indeterminate) {
            pbUpdate.isIndeterminate = true
            tvProgress.text = "已下载 ${human(p.downloaded)}"
        } else {
            pbUpdate.isIndeterminate = false
            pbUpdate.progress = p.percent
            tvProgress.text = "${p.percent}%  ·  ${human(p.downloaded)} / ${human(p.total)}"
        }
    }

    private fun human(bytes: Long): String = when {
        bytes <= 0 -> "0 B"
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> String.format("%.0f KB", bytes / 1024.0)
        else -> String.format("%.1f MB", bytes / 1024.0 / 1024.0)
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
}
