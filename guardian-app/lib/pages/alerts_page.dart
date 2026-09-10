import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/avatar_view.dart';

/// 告警中心（DESIGN 8.1 / 6.5）
class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('告警中心'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ref.read(apiProvider).markAlertsRead(all: true);
                ref.invalidate(alertsProvider);
                ref.invalidate(devicesProvider);
              } catch (_) {}
            },
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(alertsProvider);
          await ref.read(alertsProvider.future);
        },
        child: alerts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 140),
              const Icon(Icons.cloud_off, size: 64, color: Colors.black26),
              const SizedBox(height: 12),
              Center(child: Text('$e', style: const TextStyle(color: Colors.black54))),
            ],
          ),
          data: (data) {
            if (data.alerts.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 140),
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.black26),
                  SizedBox(height: 12),
                  Center(child: Text('暂无告警', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: data.alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _AlertCard(alert: data.alerts[i]),
            );
          },
        ),
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert});

  final AlertItem alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color) = switch (alert.type) {
      'OUT_OF_FENCE' => (Icons.warning_amber_rounded, const Color(0xFFE5484D)),
      'BACK_IN_FENCE' => (Icons.home_outlined, const Color(0xFF12A150)),
      'LOW_BATTERY' => (Icons.battery_alert_outlined, const Color(0xFFE5A100)),
      'OFFLINE' => (Icons.wifi_off_outlined, const Color(0xFFE5484D)),
      'RECOVERED' => (Icons.wifi_outlined, const Color(0xFF12A150)),
      'GUARD_OFF' => (Icons.vpn_lock_outlined, const Color(0xFFE5A100)),
      _ => (Icons.notifications_none, Colors.black45),
    };

    return Opacity(
      opacity: alert.read ? 0.55 : 1,
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          onTap: () async {
            if (alert.read) return;
            try {
              await ref.read(apiProvider).markAlertsRead(ids: [alert.id]);
              ref.invalidate(alertsProvider);
              ref.invalidate(devicesProvider);
            } catch (_) {}
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  alert.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: alert.read ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
              ),
              if (!alert.read)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(alert.body, style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 4),
              Row(
                children: [
                  AvatarView(base64: alert.avatar, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${alert.nickname ?? "老人"} · '
                    '${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(alert.createdAt))}',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
