package com.findma.findma_guardian

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新所需的原生能力（Dart 侧通过 MethodChannel `findma/updater` 调用）。
 *
 * 为什么不用第三方插件：权限检查 / 跳系统设置 / 拉起安装器这三个动作加起来不到 80 行，
 * 自己实现比引入两个插件（permission_handler + open_filex）更可控，也避免插件与
 * Flutter / AGP 版本互相卡住。
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "findma/updater"
        const val APK_NAME = "findma-guardian-update.apk"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 下载目录：由原生给出，Dart 侧不必再依赖 path_provider
                    "cacheDir" -> result.success(File(cacheDir, "update").apply { mkdirs() }.absolutePath)

                    "apkPath" -> result.success(apkFile().absolutePath)

                    // 是否已允许「安装未知应用」（Android 8.0+ 才有该开关）
                    "canInstall" -> result.success(canInstall())

                    // 跳到系统「安装未知应用」授权页；返回是否成功打开
                    "requestInstallPermission" -> result.success(openInstallPermissionSettings())

                    // 拉起系统安装器
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_ARGS", "缺少 path 参数", null)
                        } else {
                            try {
                                installApk(File(path))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun apkFile(): File = File(File(cacheDir, "update").apply { mkdirs() }, APK_NAME)

    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallPermissionSettings(): Boolean {
        val withPackage = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        if (tryStart(withPackage)) return true
        return tryStart(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
    }

    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun installApk(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
