import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/avatar_view.dart';

/// 老人资料页（DESIGN 8.1）：
///  · 头像 —— 设备级，所有子女共享，改这里所有人都能看到
///  · 称呼 —— 用户级，只影响当前账号的显示
///  · 解绑 —— 解除当前账号与设备的绑定
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.device});

  final DeviceSummary device;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late TextEditingController _nickname;
  late String? _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.device.nickname);
    _avatar = widget.device.avatar;
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    final base64Str = await pickAndCompressAvatar(context);
    if (base64Str == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).updateProfile(widget.device.id, avatarBase64: base64Str);
      setState(() => _avatar = base64Str);
      ref.invalidate(devicesProvider);
      _toast('头像已更新（所有子女共享）');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNickname() async {
    final name = _nickname.text.trim();
    if (name.isEmpty) {
      _toast('称呼不能为空');
      return;
    }
    if (name == widget.device.nickname) {
      _toast('称呼没有变化');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).updateProfile(widget.device.id, nickname: name);
      ref.invalidate(devicesProvider);
      _toast('称呼已更新（仅你自己可见）');
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbind() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解除绑定'),
        content: Text(
          '解绑后你将不再看到「${widget.device.nickname}」的位置与告警。\n'
          '老人手机端不受影响，其他子女也不受影响，重新扫码即可再次绑定。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认解绑'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).unbind(widget.device.id);
      ref.invalidate(devicesProvider);
      if (!mounted) return;
      _toast('已解绑');
      Navigator.pop(context);
    } on ApiException catch (e) {
      _toast(e.message);
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
      appBar: AppBar(title: const Text('老人资料')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                AvatarView(base64: _avatar, size: 104),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : _changeAvatar,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('更换头像'),
                ),
                const Text(
                  '头像是设备级的，所有绑定这位老人的子女看到的都是同一张',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nickname,
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: '我的称呼',
              border: OutlineInputBorder(),
              helperText: '仅影响你自己的显示，其他子女可以叫别的',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _saveNickname,
              child: const Text('保存称呼'),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('设备 ID'),
            subtitle: Text(widget.device.id, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE5484D),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _unbind,
            child: const Text('解除绑定'),
          ),
        ],
      ),
    );
  }
}
