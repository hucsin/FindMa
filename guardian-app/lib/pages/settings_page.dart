import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../app_config.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/update_card.dart';

/// 设置（DESIGN 8.1）：上报频率（按老人设置）、数据保留期说明、关于、退出登录
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final devices = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('账号'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(auth.username ?? '未登录'),
            subtitle: const Text('JWT 有效期 30 天'),
          ),

          const _SectionHeader('上报频率（按老人设置）'),
          devices.maybeWhen(
            data: (list) => Column(
              children: [
                for (final d in list)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(d.nickname),
                    subtitle: Text(
                      '普通 ${_mmss(d.settings.normalIntervalSec)} · '
                      '丢失 ${_mmss(d.settings.lostIntervalSec)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editIntervals(context, ref, d),
                  ),
              ],
            ),
            orElse: () => const ListTile(title: Text('加载中…', style: TextStyle(color: Colors.black45))),
          ),

          const _SectionHeader('数据保留'),
          const ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('轨迹保留期'),
            subtitle: Text('默认 180 天，由服务端 Cron 每天自动清理（可在 Worker 的 LOCATION_RETENTION_DAYS 调整）'),
            isThreeLine: true,
          ),

          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本'),
            subtitle: Text('${AppConfig.appVersion}（M1~M6 骨架）'),
          ),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('数据安全'),
            subtitle: Text('位置数据仅存于自有 Cloudflare D1，不经过第三方；老人端 token 仅存手机本地'),
            isThreeLine: true,
          ),

          const _SectionHeader('更新'),
          const UpdateCard(),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE5484D),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('退出登录'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _mmss(int sec) {
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    return s == 0 ? '${m}min' : '${m}min${s}s';
  }

  Future<void> _editIntervals(BuildContext context, WidgetRef ref, DeviceSummary device) async {
    var normal = device.settings.normalIntervalSec.toDouble();
    var lost = device.settings.lostIntervalSec.toDouble();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('${device.nickname} · 上报频率'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('普通模式 ${normal.round()} 秒',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: normal,
                min: 60,
                max: 3600,
                divisions: 59,
                label: '${normal.round()}s',
                onChanged: (v) => setState(() => normal = v),
              ),
              const SizedBox(height: 6),
              Text('丢失模式 ${lost.round()} 秒',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: lost,
                min: 15,
                max: 600,
                divisions: 39,
                label: '${lost.round()}s',
                onChanged: (v) => setState(() => lost = v),
              ),
              const Text(
                '修改后将在老人端下次上报时生效（最长延迟一个当前间隔）',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await ref.read(apiProvider).updateSettings(
            device.id,
            normalIntervalSec: normal.round(),
            lostIntervalSec: lost.round(),
          );
      ref.invalidate(devicesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已下发，等待老人端同步')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
      ),
    );
  }
}
