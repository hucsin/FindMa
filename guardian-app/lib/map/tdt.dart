import 'dart:convert';
import 'dart:math' as math;

import '../app_config.dart';

/// 天地图栅格瓦片 style（DESIGN 4.2）。
///
/// - 底图：`vec_w` 矢量底图 + `cva_w` 中文注记叠加
/// - 卫星：`img_w` 影像 + `cia_w` 注记
/// - 坐标系 CGCS2000，与 GPS 的 WGS-84 差异为厘米级 → 全链路零坐标转换
///
/// 注意：MapLibre 不支持 Leaflet 的 `{s}` 子域占位符，因此这里显式展开 t0~t7。
String tdtStyleJson({bool satellite = false}) {
  const key = AppConfig.tdtKey;
  final base = satellite ? 'img_w' : 'vec_w';
  final anno = satellite ? 'cia_w' : 'cva_w';

  List<String> urls(String layer) => List.generate(
        8,
        (i) => 'https://t$i.tianditu.gov.cn/DataServer?T=$layer&x={x}&y={y}&l={z}&tk=$key',
      );

  return jsonEncode({
    'version': 8,
    'name': 'FindMa TDT',
    'sources': {
      'tdt-base': {
        'type': 'raster',
        'tiles': urls(base),
        'tileSize': 256,
        'maxzoom': 18,
        'attribution': '© 天地图',
      },
      'tdt-anno': {
        'type': 'raster',
        'tiles': urls(anno),
        'tileSize': 256,
        'maxzoom': 18,
      },
    },
    'layers': [
      {'id': 'tdt-base-layer', 'type': 'raster', 'source': 'tdt-base', 'minzoom': 0, 'maxzoom': 22},
      {'id': 'tdt-anno-layer', 'type': 'raster', 'source': 'tdt-anno', 'minzoom': 0, 'maxzoom': 22},
    ],
  });
}

/// 把圆围栏近似成 64 边多边形，用于在地图上画"真实米制半径"的圆
/// （MapLibre 的 circle 图层半径是像素，不是米，所以必须走 GeoJSON）
Map<String, dynamic> circleGeoJson(double lat, double lng, double radiusM) {
  const steps = 64;
  final ring = <List<double>>[];
  final latRad = lat * math.pi / 180;

  for (var i = 0; i <= steps; i++) {
    final angle = 2 * math.pi * i / steps;
    final dLat = (radiusM * math.cos(angle)) / 111320.0;
    final dLng = (radiusM * math.sin(angle)) / (111320.0 * math.cos(latRad));
    // GeoJSON 是 [lng, lat] 顺序
    ring.add([lng + dLng, lat + dLat]);
  }

  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
      },
    ],
  };
}

/// 多边形围栏（[[lat,lng],...]）→ GeoJSON
Map<String, dynamic> polygonGeoJson(List<List<double>> polygon) {
  final ring = polygon.map((p) => [p[1], p[0]]).toList();
  if (ring.isNotEmpty) ring.add(ring.first); // 闭合

  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
      },
    ],
  };
}

/// 轨迹点 → GeoJSON LineString
Map<String, dynamic> lineGeoJson(List<List<double>> lngLat) {
  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': lngLat,
        },
      },
    ],
  };
}

/// 单点 → GeoJSON Point
Map<String, dynamic> pointGeoJson(double lat, double lng) => {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
        },
      ],
    };
