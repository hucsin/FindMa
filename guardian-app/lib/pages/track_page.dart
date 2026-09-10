import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../map/tdt.dart';
import '../models/models.dart';
import '../state/providers.dart';

/// 轨迹回放（DESIGN 8.1 / M6）：时间区间 → 地图 Polyline + 关键点列表
class TrackPage extends ConsumerStatefulWidget {
  const TrackPage({super.key, required this.device});

  final DeviceSummary device;

  @override
  ConsumerState<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends ConsumerState<TrackPage> {
  MapLibreMapController? _map;
  bool _styleReady = false;
  bool _lineDrawn = false;
  bool _loading = true;
  String? _error;

  List<LocPoint> _points = const [];
  String _range = 'today';

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _rangeOf(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (key) {
      'yesterday' => (today.subtract(const Duration(days: 1)), today),
      'week' => (today.subtract(const Duration(days: 7)), now),
      _ => (today, now),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (from, to) = _rangeOf(_range);
    try {
      final pts = await ref.read(apiProvider).track(
            widget.device.id,
            from: from,
            to: to,
            limit: 1000,
          );
      if (!mounted) return;
      setState(() => _points = pts);
      await _draw();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _safe(Future<void> Function() a) async {
    try {
      await a();
    } catch (_) {}
  }

  Future<void> _draw() async {
    final map = _map;
    if (map == null || !_styleReady || _points.isEmpty) return;

    if (_lineDrawn) {
      await _safe(() => map.removeLayer('track-line'));
      await _safe(() => map.removeSource('track'));
    }
    await _safe(() => map.addGeoJsonSource(
          'track',
          lineGeoJson(_points.map((p) => [p.lng, p.lat]).toList()),
        ));
    await _safe(() => map.addLineLayer(
          'track',
          'track-line',
          const LineLayerProperties(lineColor: '#2F6BFF', lineWidth: 4, lineOpacity: 0.85),
        ));
    _lineDrawn = true;

    // 视野包住整条轨迹
    var minLat = _points.first.lat, maxLat = _points.first.lat;
    var minLng = _points.first.lng, maxLng = _points.first.lng;
    for (final p in _points) {
      minLat = p.lat < minLat ? p.lat : minLat;
      maxLat = p.lat > maxLat ? p.lat : maxLat;
      minLng = p.lng < minLng ? p.lng : minLng;
      maxLng = p.lng > maxLng ? p.lng : maxLng;
    }
    await _safe(() => map.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            left: 48,
            right: 48,
            top: 48,
            bottom: 220,
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.device.nickname} · 轨迹回放')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final (key, label) in const [
                  ('today', '今天'),
                  ('yesterday', '昨天'),
                  ('week', '近 7 天'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _range == key,
                      onSelected: (_) {
                        setState(() => _range = key);
                        _lineDrawn = false;
                        _load();
                      },
                    ),
                  ),
                const Spacer(),
                if (_loading)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: tdtStyleJson(),
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(31.2304, 121.4737),
                    zoom: 13,
                  ),
                  rotateGesturesEnabled: false,
                  onMapCreated: (c) => _map = c,
                  onStyleLoadedCallback: () {
                    _styleReady = true;
                    _draw();
                  },
                ),
                if (_error != null)
                  Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 8),
                            OutlinedButton(onPressed: _load, child: const Text('重试')),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_loading && _error == null && _points.isEmpty)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('该时间区间内没有轨迹数据', style: TextStyle(color: Colors.black54)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 190,
            child: _KeyPoints(points: _points),
          ),
        ],
      ),
    );
  }
}

class _KeyPoints extends StatelessWidget {
  const _KeyPoints({required this.points});

  final List<LocPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final fmt = DateFormat('MM-dd HH:mm:ss');

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              '共 ${points.length} 个点（服务端已抽稀）',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: points.length,
              reverse: true,
              itemBuilder: (context, i) {
                final p = points[points.length - 1 - i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 18),
                  title: Text(
                    '${p.lng.toStringAsFixed(5)}, ${p.lat.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${fmt.format(DateTime.fromMillisecondsSinceEpoch(p.reportedAt))}'
                    '${p.accuracy != null ? ' · ±${p.accuracy!.round()}m' : ''}'
                    '${p.battery != null ? ' · ${p.battery!.round()}%' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
