import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/api_client.dart';
import '../app_config.dart';
import '../state/providers.dart';
import '../widgets/avatar_view.dart';

/// 扫码绑定（DESIGN 5.4 / 8.1）
/// 二维码内容带 FINDMA-BIND: 前缀，识别到即自动进入绑定流程；也支持手动输入明文绑定码。
class BindScanPage extends StatefulWidget {
  const BindScanPage({super.key});

  @override
  State<BindScanPage> createState() => _BindScanPageState();
}

class _BindScanPageState extends State<BindScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handled = false;
  bool _torchOn = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    final code = raw.startsWith(AppConfig.bindPrefix)
        ? raw.substring(AppConfig.bindPrefix.length)
        : raw;
    if (code.trim().isEmpty) return;

    _handled = true;
    _controller.stop();
    _goToForm(code.trim());
  }

  Future<void> _goToForm(String bindCode) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BindFormPage(bindCode: bindCode)),
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context, true);
    } else {
      // 用户返回，允许重新扫描
      _handled = false;
      _controller.start();
    }
  }

  Future<void> _manualInput() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入绑定码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: '例如 A2C4E6G8',
            helperText: '老人在手机状态页可看到明文绑定码',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim().toUpperCase()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    _controller.stop();
    await _goToForm(code);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描绑定码'),
        actions: [
          IconButton(
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 取景框
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Column(
              children: [
                const Text(
                  '对准老人手机上的二维码',
                  style: TextStyle(color: Colors.white, fontSize: 15, shadows: [
                    Shadow(blurRadius: 6, color: Colors.black54),
                  ]),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _manualInput,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('手动输入绑定码'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 绑定引导页：填写称呼（必填）+ 头像（可选）→ 提交绑定
class BindFormPage extends ConsumerStatefulWidget {
  const BindFormPage({super.key, required this.bindCode});

  final String bindCode;

  @override
  ConsumerState<BindFormPage> createState() => _BindFormPageState();
}

class _BindFormPageState extends ConsumerState<BindFormPage> {
  final _nickname = TextEditingController();
  String? _avatarBase64;
  bool _busy = false;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final base64Str = await pickAndCompressAvatar(context);
    if (base64Str == null) return;
    setState(() => _avatarBase64 = base64Str);
  }

  Future<void> _submit() async {
    final nickname = _nickname.text.trim();
    if (nickname.isEmpty) {
      _toast('请填写对老人的称呼，例如「爸爸」「爷爷」');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).bind(
            widget.bindCode,
            nickname,
            avatarBase64: _avatarBase64,
          );
      ref.invalidate(devicesProvider);
      if (!mounted) return;
      _toast('绑定成功');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('绑定失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加老人')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: _avatarBase64 == null
                      ? Container(
                          width: 96,
                          height: 96,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8EEFF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add_a_photo_outlined, size: 32),
                        )
                      : AvatarView(base64: _avatarBase64, size: 96),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _pickAvatar,
                  child: Text(_avatarBase64 == null ? '设置头像（可选）' : '更换头像'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nickname,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: '称呼（必填）',
              hintText: '例如 爸爸 / 爷爷 / 奶奶',
              border: OutlineInputBorder(),
              helperText: '每个子女可以各自设置自己的称呼，互不影响',
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '绑定码：${widget.bindCode}\n头像为设备级，所有子女共享同一张。',
              style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('完成绑定', style: TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }
}
