import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/avatar_view.dart';
import 'alerts_page.dart';
import 'bind_page.dart';
import 'device_detail_page.dart';
import 'settings_page.dart';

/// 老人列表（多老人管理，DESIGN 8.1）
class DeviceListPage extends ConsumerWidget {
  const DeviceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final alerts = ref.watch(alertsProvider);
    final unread = alerts.maybeWhen(data: (d) => d.unreadTotal, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的老人'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsPage()),
            ),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_none),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BindScanPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('添加老人'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(devicesProvider);
          ref.invalidate(alertsProvider);
          await ref.read(devicesProvider.future);
        },
        child: devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(devicesProvider),
          ),
          data: (list) {
            if (list.isEmpty) return const _EmptyView();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _DeviceCard(device: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = device.lastLocation;
    final timeText = device.lastSeenAt == null
        ? '尚未上报'
        : DateFormat('MM-dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(device.lastSeenAt!),
          );

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DeviceDetailPage(device: device)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AvatarView(base64: device.avatar, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          device.nickname,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        _ModeChip(label: device.settings.modeLabel, mode: device.settings.mode),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      device.online ? '最后上报 $timeText' : '已失联 · 最后 $timeText',
                      style: TextStyle(
                        fontSize: 13,
                        color: device.online ? Colors.black54 : const Color(0xFFE5484D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (loc?.battery != null)
                          _Meta(icon: Icons.battery_std, text: '${loc!.battery!.round()}%'),
                        if (loc?.inFence != null)
                          _Meta(
                            icon: loc!.inFence! ? Icons.home_outlined : Icons.warning_amber_outlined,
                            text: loc.inFence! ? '在围栏内' : '已出围栏',
                            color: loc.inFence! ? const Color(0xFF12A150) : const Color(0xFFE5484D),
                          ),
                        if (device.settings.syncState == 'pending')
                          const _Meta(icon: Icons.sync_problem, text: '待设备同步'),
                      ],
                    ),
                  ],
                ),
              ),
              if (device.unreadAlerts > 0)
                Badge(label: Text('${device.unreadAlerts}'), child: const SizedBox(width: 8)),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black54;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.mode});

  final String label;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final color = switch (mode) {
      'LOST' => const Color(0xFFE5484D),
      'WATCH' => const Color(0xFF2F6BFF),
      _ => Colors.black45,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.qr_code_scanner, size: 72, color: Colors.black26),
        SizedBox(height: 16),
        Center(
          child: Text(
            '还没有绑定老人\n点右下角「添加老人」扫描老人手机上的二维码',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.6),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 140),
        const Icon(Icons.cloud_off, size: 64, color: Colors.black26),
        const SizedBox(height: 16),
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        )),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: onRetry, child: const Text('重试'))),
      ],
    );
  }
}
