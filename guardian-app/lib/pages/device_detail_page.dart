import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../api/api_client.dart';
import '../map/tdt.dart';
import '../models/models.dart';
import '../state/providers.dart';
import 'alerts_page.dart';
import 'fence_page.dart';
import 'profile_page.dart';
import 'track_page.dart';

/// 地图首页（DESIGN 8.1）：最新位置 + 围栏叠加 + 模式切换 + 电量/最后上报
class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key, required this.device});

  final DeviceSummary device;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  MapLibreMapController? _map;
  Timer? _poll;

  bool _styleReady = false;
  bool _centered = false;
  bool _markerDrawn = false;
  bool _fenceDrawn = false;
  bool _busy = false;

  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _refresh();
    // 前台轮询最新位置（DESIGN 8.2 的 30s 节奏）
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await ref.read(apiProvider).summary(widget.device.id);
      if (!mounted) return;
      setState(() => _summary = s);
      await _draw();
    } catch (_) {
      // 静默失败：保留上一次的位置展示
    }
  }

  /// MapLibre 的图层/数据源 API 在不同版本上细节略有差异，
  /// 这里统一包一层容错，避免某一层已存在时整体抛断。
  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> _draw() async {
    final map = _map;
    final s = _summary;
    if (map == null || s == null || !_styleReady) return;

    // ① 老人当前位置
    final loc = s['lastLocation'] as Map<String, dynamic>?;
    if (loc != null) {
      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();

      if (_markerDrawn) {
        await _safe(() => map.removeLayer('elder-circle'));
        await _safe(() => map.removeSource('elder-pos'));
      }
      await _safe(() => map.addGeoJsonSource('elder-pos', pointGeoJson(lat, lng)));
      await _safe(() => map.addCircleLayer(
            'elder-pos',
            'elder-circle',
            const CircleLayerProperties(
              circleColor: '#2F6BFF',
              circleRadius: 9,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 3,
            ),
          ));
      _markerDrawn = true;

      if (!_centered) {
        _centered = true;
        await _safe(() => map.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16)));
      }
    }

    // ② 电子围栏叠加
    final fence = s['fence'] as Map<String, dynamic>?;
    if (fence != null && fence['enabled'] != false) {
      if (_fenceDrawn) {
        await _safe(() => map.removeLayer('fence-line'));
        await _safe(() => map.removeLayer('fence-fill'));
        await _safe(() => map.removeSource('fence'));
      }

      Map<String, dynamic> geo;
      if (fence['type'] == 'polygon') {
        final poly = ((fence['polygon'] as List?) ?? const [])
            .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
            .toList();
        if (poly.length < 3) return;
        geo = polygonGeoJson(poly);
      } else {
        geo = circleGeoJson(
          (fence['centerLat'] as num).toDouble(),
          (fence['centerLng'] as num).toDouble(),
          (fence['radiusM'] as num).toDouble(),
        );
      }

      await _safe(() => map.addGeoJsonSource('fence', geo));
      await _safe(() => map.addFillLayer(
            'fence',
            'fence-fill',
            const FillLayerProperties(fillColor: '#2F6BFF', fillOpacity: 0.12),
          ));
      await _safe(() => map.addLineLayer(
            'fence',
            'fence-line',
            const LineLayerProperties(lineColor: '#2F6BFF', lineWidth: 2),
          ));
      _fenceDrawn = true;
    }
  }

  Future<void> _switchMode(String mode) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final settings = await ref.read(apiProvider).updateSettings(widget.device.id, mode: mode);
      ref.invalidate(devicesProvider);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换为「${settings.modeLabel}」模式，将在老人端下次上报时生效'),
        ),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('切换失败：$e');
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
    final s = _summary;
    final settings = _settingsOf(s);
    final loc = s?['lastLocation'] as Map<String, dynamic>?;

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: tdtStyleJson(),
            initialCameraPosition: const CameraPosition(
              target: LatLng(31.2304, 121.4737),
              zoom: 12,
            ),
            onMapCreated: (controller) => _map = controller,
            onStyleLoadedCallback: () {
              _styleReady = true;
              _draw();
            },
            compassEnabled: false,
            rotateGesturesEnabled: false,
          ),

          // 顶部信息卡
          _TopCard(
            title: widget.device.nickname,
            subtitle: _subtitle(s),
            online: _onlineOf(s, settings),
            onBack: () => Navigator.pop(context),
            onRefresh: _refresh,
            onAlerts: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsPage()),
            ),
            onProfile: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProfilePage(device: widget.device)),
            ),
          ),

          // 底部：模式切换 + 快捷入口
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ModeSwitcher(
                  current: settings?.mode ?? 'NORMAL',
                  busy: _busy,
                  onChanged: _switchMode,
                ),
                const SizedBox(height: 10),
                _BottomBar(
                  device: widget.device,
                  loc: loc,
                  syncState: settings?.syncState ?? 'synced',
                  onTrack: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TrackPage(device: widget.device)),
                  ),
                  onFence: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FencePage(device: widget.device)),
                  ).then((_) => _refresh()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 优先用 summary 里的配置，回退到列表页带入的配置
  DeviceSettings? _settingsOf(Map<String, dynamic>? s) {
    if (s == null) return widget.device.settings;
    final raw = s['settings'] as Map<String, dynamic>?;
    return raw == null ? widget.device.settings : DeviceSettings.fromJson(raw);
  }

  bool _onlineOf(Map<String, dynamic>? s, DeviceSettings? settings) {
    if (s == null) return widget.device.online;
    return s['online'] as bool? ?? false;
  }

  String _subtitle(Map<String, dynamic>? s) {
    final loc = s?['lastLocation'] as Map<String, dynamic>?;
    final at = (s?['lastSeenAt'] as num?)?.toInt() ?? widget.device.lastSeenAt;
    if (at == null) return '尚未收到上报';
    final time = DateFormat('MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(at));

    final parts = <String>['最后上报 $time'];
    if (loc?['battery'] != null) {
      parts.add('电量 ${(loc!['battery'] as num).round()}%');
    }
    if (loc?['inFence'] != null) {
      parts.add(loc!['inFence'] == true ? '在围栏内' : '已出围栏');
    }
    return parts.join(' · ');
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.title,
    required this.subtitle,
    required this.online,
    required this.onBack,
    required this.onRefresh,
    required this.onAlerts,
    required this.onProfile,
  });

  final String title;
  final String subtitle;
  final bool online;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onAlerts;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          elevation: 2,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
            child: Row(
              children: [
                IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: (online ? const Color(0xFF12A150) : const Color(0xFFE5484D))
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              online ? '在线' : '失联',
                              style: TextStyle(
                                fontSize: 11,
                                color: online ? const Color(0xFF12A150) : const Color(0xFFE5484D),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                IconButton(onPressed: onAlerts, icon: const Icon(Icons.notifications_none)),
                IconButton(onPressed: onProfile, icon: const Icon(Icons.more_horiz)),
                IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.current, required this.busy, required this.onChanged});

  final String current;
  final bool busy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const modes = [
      ('NORMAL', '普通', Icons.shield_outlined),
      ('WATCH', '关注', Icons.visibility_outlined),
      ('LOST', '丢失', Icons.sos_outlined),
    ];

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final (value, label, icon) in modes)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: busy ? null : () => onChanged(value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: current == value
                          ? (value == 'LOST'
                              ? const Color(0xFFE5484D).withValues(alpha: 0.12)
                              : const Color(0xFF2F6BFF).withValues(alpha: 0.12))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: current == value
                              ? (value == 'LOST' ? const Color(0xFFE5484D) : const Color(0xFF2F6BFF))
                              : Colors.black45,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: current == value ? FontWeight.bold : FontWeight.normal,
                            color: current == value ? Colors.black87 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.device,
    required this.loc,
    required this.syncState,
    required this.onTrack,
    required this.onFence,
  });

  final DeviceSummary device;
  final Map<String, dynamic>? loc;
  final String syncState;
  final VoidCallback onTrack;
  final VoidCallback onFence;

  @override
  Widget build(BuildContext context) {
    final acc = (loc?['accuracy'] as num?)?.round();
    final provider = loc?['provider'] as String?;

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loc != null)
              Text(
                '经度 ${(loc!['lng'] as num).toStringAsFixed(5)} · '
                '纬度 ${(loc!['lat'] as num).toStringAsFixed(5)}'
                '${acc != null ? ' · 精度 ±${acc}m' : ''}'
                '${provider != null ? ' · $provider' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              )
            else
              const Text('暂无位置数据', style: TextStyle(fontSize: 12, color: Colors.black54)),
            if (syncState == 'pending')
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '配置待设备同步（将在老人端下次上报时生效）',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE5A100)),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTrack,
                    icon: const Icon(Icons.timeline, size: 18),
                    label: const Text('轨迹回放'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onFence,
                    icon: const Icon(Icons.home_work_outlined, size: 18),
                    label: const Text('电子围栏'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
