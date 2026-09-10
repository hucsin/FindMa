import 'package:flutter/material.dart';

import '../app_config.dart';
import '../update/updater.dart';

/// 设置页的「软件更新」卡片。
///
/// 交互流程（按需求）：
///   点击按钮 → 先检查「安装未知应用」权限
///      ├─ 没有 → 跳系统设置授权页，用户回来后自动继续
///      └─ 有   → 从 [AppConfig.updateUrl] 下载，按钮下方实时显示进度
///                 下载完成 → 拉起系统安装器
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> with WidgetsBindingObserver {
  static const Color _brand = Color(0xFF2F6BFF);

  bool _canInstall = true;
  bool _downloading = false;

  /// 因为缺权限跳去了系统设置，回来后要自动接着下载
  bool _awaitingPermission = false;

  UpdateProgress? _progress;
  String? _status;
  String? _error;

  /// 进度回调可能非常密集，做节流避免每来一个数据块就整树重建
  int _lastTickMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _onResumed();
  }

  // ───────────────────────────── 权限 ─────────────────────────────

  Future<void> _refreshPermission() async {
    final ok = await Updater.canInstall();
    if (!mounted) return;
    setState(() => _canInstall = ok);
  }

  Future<void> _onResumed() async {
    final ok = await Updater.canInstall();
    if (!mounted) return;
    setState(() => _canInstall = ok);

    if (!_awaitingPermission) return;
    _awaitingPermission = false;

    if (ok) {
      await _startDownload();
    } else {
      setState(() => _status = '尚未允许「安装未知应用」');
    }
  }

  // ───────────────────────────── 主流程 ─────────────────────────────

  Future<void> _onPressed() async {
    if (_downloading) {
      _snack('正在下载中，请稍候…');
      return;
    }

    final ok = await Updater.canInstall();
    if (!mounted) return;
    setState(() => _canInstall = ok);

    if (!ok) {
      setState(() {
        _awaitingPermission = true;
        _error = null;
        _status = '需要先允许「安装未知应用」，正在打开系统设置…';
      });
      final opened = await Updater.requestInstallPermission();
      if (!mounted) return;
      if (!opened) {
        setState(() {
          _awaitingPermission = false;
          _status = null;
          _error = '无法打开授权页面，请到 系统设置 → 应用 → 特殊权限 中手动允许';
        });
      }
      return;
    }

    await _startDownload();
  }

  Future<void> _startDownload() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = const UpdateProgress(received: 0, total: -1);
      _status = '正在连接 ${Uri.parse(AppConfig.updateUrl).host} …';
    });

    try {
      final path = await Updater.download(
        onProgress: (p) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final finished = !p.indeterminate && p.received >= p.total;
          if (!finished && now - _lastTickMs < 100) return;
          _lastTickMs = now;
          if (!mounted) return;
          setState(() {
            _progress = p;
            _status = p.indeterminate
                ? '已下载 ${_human(p.received)}'
                : '${p.percent}%  ·  ${_human(p.received)} / ${_human(p.total)}';
          });
        },
      );
      if (!mounted) return;
      setState(() => _status = '下载完成，正在启动安装…');
      await Updater.install(path);
      if (!mounted) return;
      setState(() => _status = '已交给系统安装器，请在弹窗中点「安装」');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = null;
        _error = '更新失败：$e';
      });
      return;
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ───────────────────────────── 渲染 ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final showProgress = _downloading || _status != null || _error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.system_update),
          title: const Text('软件更新'),
          subtitle: Text(
            '当前版本 ${AppConfig.appVersion}\n'
            '${Uri.parse(AppConfig.updateUrl).host}',
          ),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 触发按钮 ──
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: _brand,
                ),
                onPressed: _downloading ? null : _onPressed,
                icon: Icon(_downloading ? Icons.hourglass_top : Icons.download),
                label: Text(_downloading ? '正在下载…' : '下载并安装新版本'),
              ),

              // ── 按钮下方：下载进度 ──
              if (showProgress) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _error != null ? 0 : p?.fraction,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE3E7EF),
                    valueColor: const AlwaysStoppedAnimation<Color>(_brand),
                  ),
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
                  )
                else
                  Text(
                    _status ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ] else if (!_canInstall) ...[
                const SizedBox(height: 8),
                const Text(
                  '尚未允许「安装未知应用」，点击按钮会先跳到系统设置授权',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE5A00D)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _human(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
