import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

/// 下载进度。`total <= 0` 表示服务端没有返回 Content-Length，此时只能显示已下载字节数。
class UpdateProgress {
  const UpdateProgress({required this.received, required this.total});

  final int received;
  final int total;

  bool get indeterminate => total <= 0;

  /// 供 LinearProgressIndicator 使用；不确定进度时返回 null（走动画）
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  int get percent => total > 0 ? ((received * 100) ~/ total).clamp(0, 100) : 0;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 应用内更新：权限检查 / 跳系统设置 / 下载 APK / 拉起安装器。
///
/// 原生侧实现见 `android/.../MainActivity.kt`（MethodChannel `findma/updater`）。
/// 不走第三方插件，避免插件与 Flutter / AGP 版本互相卡住。
class Updater {
  const Updater._();

  static const MethodChannel _channel = MethodChannel('findma/updater');

  /// 是否已允许「安装未知应用」（Android 8.0+ 的特殊权限，只能由用户在系统设置里开）
  static Future<bool> canInstall() async {
    final ok = await _channel.invokeMethod<bool>('canInstall');
    return ok ?? false;
  }

  /// 跳转到系统「安装未知应用」授权页，返回是否成功打开
  static Future<bool> requestInstallPermission() async {
    final ok = await _channel.invokeMethod<bool>('requestInstallPermission');
    return ok ?? false;
  }

  /// 把下载好的 APK 交给系统安装器
  static Future<void> install(String path) async {
    await _channel.invokeMethod<bool>('install', {'path': path});
  }

  /// 流式下载到应用缓存目录，返回 APK 的绝对路径。
  ///
  /// 先写 `.part` 再改名，避免中途失败留下半包被系统当成完整 APK 安装。
  static Future<String> download({
    void Function(UpdateProgress progress)? onProgress,
  }) async {
    final path = await _channel.invokeMethod<String>('apkPath');
    if (path == null || path.isEmpty) {
      throw const UpdateException('无法获取应用缓存目录');
    }

    final target = File(path);
    final tmp = File('$path.part');
    if (await tmp.exists()) await tmp.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(AppConfig.updateUrl))
        ..headers['User-Agent'] = 'FindMa-Guardian/${AppConfig.appVersion}';

      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw UpdateException('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? -1;
      var received = 0;
      onProgress?.call(UpdateProgress(received: 0, total: total));

      final sink = tmp.openWrite();
      try {
        // 相邻数据块间隔超过 30s 视为断流
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(UpdateProgress(received: received, total: total));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      onProgress?.call(UpdateProgress(received: received, total: total));
      return target.path;
    } finally {
      client.close();
    }
  }
}
