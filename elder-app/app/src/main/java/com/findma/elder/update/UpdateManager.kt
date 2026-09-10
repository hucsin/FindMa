package com.findma.elder.update

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.findma.elder.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * 应用内更新（设置页）：下载新版本 APK → 拉起系统安装器。
 *
 * 关键点：
 *  1) Android 8.0+ 必须显式获得「安装未知应用」授权，否则安装器会直接拒绝；
 *     这是一个**特殊权限**（不是运行时权限），只能跳到系统设置页让用户手动开。
 *  2) 下载先写 `.part` 再改名，避免网络中断留下半包被当成完整 APK 安装。
 *  3) APK 通过 FileProvider 以 content:// 暴露，不能用 file://（Android 7.0+ 会抛
 *     FileUriExposedException）。
 */
object UpdateManager {

    private const val APK_NAME = "findma-elder-update.apk"

    /** 是否已允许安装来自本应用的未知来源 APK */
    fun canInstall(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /**
     * 跳转到系统「安装未知应用」授权页。
     * 部分 ROM 不支持带 package 的深链，降级到不带参数的列表页。
     */
    fun openInstallPermissionSettings(activity: Activity): Boolean {
        val withPackage = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}"),
        )
        if (tryStart(activity, withPackage)) return true
        return tryStart(activity, Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
    }

    private fun tryStart(activity: Activity, intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    data class Progress(val downloaded: Long, val total: Long) {
        /** 服务器未返回 Content-Length 时为 true，此时只能显示已下载字节数 */
        val indeterminate: Boolean get() = total <= 0
        val percent: Int
            get() = if (total > 0) ((downloaded * 100) / total).toInt().coerceIn(0, 100) else 0
    }

    private fun apkFile(context: Context): File =
        File(File(context.cacheDir, "update").apply { mkdirs() }, APK_NAME)

    /**
     * 流式下载，边下边回调进度。回调发生在 IO 线程，调用方需自行切回主线程。
     */
    suspend fun download(context: Context, onProgress: (Progress) -> Unit): File =
        withContext(Dispatchers.IO) {
            val target = apkFile(context)
            val tmp = File(target.absolutePath + ".part")
            if (tmp.exists()) tmp.delete()

            val client = OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .build()

            val request = Request.Builder()
                .url(BuildConfig.UPDATE_URL)
                .header("User-Agent", BuildConfig.APP_USER_AGENT)
                .build()

            client.newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
                val body = resp.body ?: throw IOException("响应为空")
                val total = body.contentLength()
                var downloaded = 0L
                onProgress(Progress(0L, total))

                body.byteStream().use { input ->
                    FileOutputStream(tmp).use { output ->
                        val buf = ByteArray(64 * 1024)
                        var lastReportAt = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            output.write(buf, 0, n)
                            downloaded += n
                            // 限流：最多约 12 次/秒，避免高频刷新 UI
                            val now = System.currentTimeMillis()
                            if (now - lastReportAt >= 80) {
                                lastReportAt = now
                                onProgress(Progress(downloaded, total))
                            }
                        }
                        output.flush()
                        output.fd.sync()
                    }
                }
                onProgress(Progress(downloaded, total))
            }

            if (target.exists()) target.delete()
            if (!tmp.renameTo(target)) {
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
            target
        }

    /** 拉起系统安装器；安装过程中的确认弹窗由系统负责 */
    fun install(context: Context, apk: File) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apk,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
