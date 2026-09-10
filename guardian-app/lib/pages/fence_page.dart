import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../api/api_client.dart';
import '../map/tdt.dart';
import '../models/models.dart';
import '../state/providers.dart';

/// 围栏编辑（DESIGN 8.1 / M4）：
/// 在地图上长按选圆心 → 拖滑块调半径 → 保存。
/// 围栏计算全部在 Worker 完成，老人手机零负担（DESIGN 6.4）。
class FencePage extends ConsumerStatefulWidget {
  const FencePage({super.key, required this.device});

  final DeviceSummary device;

  @override
  ConsumerState<FencePage> createState() => _FencePageState();
}

class _FencePageState extends ConsumerState<FencePage> {
  MapLibreMapController? _map;
  bool _styleReady = false;
  bool _drawn = false;
  bool _loading = true;
  bool _saving = false;

  double? _centerLat;
  double? _centerLng;
  double _radiusM = 300;
  bool _enabled = true;
  String _name = '家';
  bool _multiPolygon = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final fence = await ref.read(apiProvider).getFence(widget.device.id);
      if (!mounted) return;
      if (fence != null) {
        setState(() {
          _multiPolygon = fence.type == 'polygon';
          _name = fence.name;
          _enabled = fence.enabled;
          if (fence.type == 'circle') {
            _centerLat = fence.centerLat;
            _centerLng = fence.centerLng;
            _radiusM = fence.radiusM ?? 300;
          }
        });
      }
    } catch (_) {
      // 忽略：没有围栏时保持空白状态
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _draw();
  }

  Future<void> _safe(Future<void> Function() a) async {
    try {
      await a();
    } catch (_) {}
  }

  Future<void> _draw() async {
    final map = _map;
    if (map == null || !_styleReady || _centerLat == null || _centerLng == null) return;

    if (_drawn) {
      await _safe(() => map.removeLayer('draft-line'));
      await _safe(() => map.removeLayer('draft-fill'));
      await _safe(() => map.removeSource('draft'));
    }
    await _safe(() => map.addGeoJsonSource(
          'draft',
          circleGeoJson(_centerLat!, _centerLng!, _radiusM),
        ));
    await _safe(() => map.addFillLayer(
          'draft',
          'draft-fill',
          const FillLayerProperties(fillColor: '#2F6BFF', fillOpacity: 0.14),
        ));
    await _safe(() => map.addLineLayer(
          'draft',
          'draft-line',
          const LineLayerProperties(lineColor: '#2F6BFF', lineWidth: 2),
        ));
    _drawn = true;
  }

  Future<void> _save() async {
    if (_centerLat == null || _centerLng == null) {
      _toast('请先在地图上长按选择围栏中心');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).saveCircleFence(
            widget.device.id,
            centerLat: _centerLat!,
            centerLng: _centerLng!,
            radiusM: _radiusM,
            name: _name,
            enabled: _enabled,
          );
      ref.invalidate(devicesProvider);
      if (!mounted) return;
      _toast('围栏已保存，将在老人端下次上报后生效');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device.nickname} · 电子围栏'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                MapLibreMap(
                  styleString: tdtStyleJson(),
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _centerLat ?? widget.device.lastLocation?.lat ?? 31.2304,
                      _centerLng ?? widget.device.lastLocation?.lng ?? 121.4737,
                    ),
                    zoom: 15,
                  ),
                  rotateGesturesEnabled: false,
                  onMapCreated: (c) => _map = c,
                  onStyleLoadedCallback: () {
                    _styleReady = true;
                    _draw();
                  },
                  onMapLongClick: (_, point) async {
                    setState(() {
                      _centerLat = point.latitude;
                      _centerLng = point.longitude;
                    });
                    await _draw();
                  },
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: Card(
                    elevation: 2,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.home_work_outlined, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(text: _name),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '围栏名称',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => _name = v,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Switch(
                                value: _enabled,
                                onChanged: (v) => setState(() => _enabled = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _centerLat == null
                                ? '在地图上长按选择围栏中心'
                                : '中心 ${_centerLng!.toStringAsFixed(5)}, ${_centerLat!.toStringAsFixed(5)}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('半径', style: TextStyle(fontSize: 13)),
                              Expanded(
                                child: Slider(
                                  value: _radiusM,
                                  min: 50,
                                  max: 2000,
                                  divisions: 39,
                                  label: '${_radiusM.round()} m',
                                  onChanged: (v) {
                                    setState(() => _radiusM = v);
                                    _draw();
                                  },
                                ),
                              ),
                              Text('${_radiusM.round()} m',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          if (_multiPolygon)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                '当前设备已有「多边形」围栏。保存圆形围栏会将其替换（MVP 每设备一个围栏）。',
                                style: TextStyle(fontSize: 11, color: Color(0xFFE5A100)),
                              ),
                            ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  final loc = widget.device.lastLocation;
                                  if (loc == null) {
                                    _toast('还没有位置数据');
                                    return;
                                  }
                                  setState(() {
                                    _centerLat = loc.lat;
                                    _centerLng = loc.lng;
                                  });
                                  await _draw();
                                },
                                icon: const Icon(Icons.my_location, size: 16),
                                label: const Text('以当前位置为圆心'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
