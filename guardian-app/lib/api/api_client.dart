import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/models.dart';

/// 服务端返回的业务错误
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);

  @override
  String toString() => message;
}

/// FindMa 子女端 API 客户端（DESIGN 6.2）。
/// 鉴权：登录后所有请求带 `Authorization: Bearer <JWT>`。
class ApiClient {
  ApiClient({String? baseUrl}) : _base = baseUrl ?? AppConfig.apiBase;

  final String _base;
  String? _token;

  String? get token => _token;
  void setToken(String? value) => _token = value;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ── 鉴权 ────────────────────────────────────────────────────────────────
  Future<AuthResult> register(String username, String password) async {
    final json = await _post('/auth/register', {'username': username, 'password': password});
    return AuthResult.fromJson(json);
  }

  Future<AuthResult> login(String username, String password) async {
    final json = await _post('/auth/login', {'username': username, 'password': password});
    return AuthResult.fromJson(json);
  }

  // ── 设备 ────────────────────────────────────────────────────────────────
  Future<List<DeviceSummary>> listDevices() async {
    final json = await _get('/devices');
    return ((json['devices'] as List?) ?? const [])
        .map((e) => DeviceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 扫码绑定：bindCode + 称呼（必填）+ 头像 base64（可选，设备级共享）
  Future<DeviceSummary> bind(String bindCode, String nickname, {String? avatarBase64}) async {
    final json = await _post('/devices/bind', {
      'bindCode': bindCode,
      'nickname': nickname,
      if (avatarBase64 != null) 'avatar': avatarBase64,
    });
    final device = json['device'] as Map<String, dynamic>;
    return DeviceSummary(
      id: device['id'] as String,
      name: device['name'] as String? ?? '老人手机',
      nickname: device['nickname'] as String? ?? nickname,
      avatar: device['avatar'] as String?,
      lastSeenAt: null,
      online: false,
      unreadAlerts: 0,
      settings: DeviceSettings.fromJson(const {}),
      lastLocation: null,
    );
  }

  Future<void> updateProfile(String deviceId, {String? nickname, String? avatarBase64}) async {
    await _put('/devices/$deviceId/profile', {
      if (nickname != null) 'nickname': nickname,
      if (avatarBase64 != null) 'avatar': avatarBase64,
    });
  }

  /// 解除当前账号与设备的绑定（不影响老人端，也不影响其他子女）
  Future<void> unbind(String deviceId) async {
    await _send(() => http.delete(Uri.parse('$_base/devices/$deviceId/bind'), headers: _headers));
  }

  Future<Map<String, dynamic>> summary(String deviceId) => _get('/devices/$deviceId/summary');

  Future<List<LocPoint>> track(
    String deviceId, {
    required DateTime from,
    required DateTime to,
    int limit = 1000,
  }) async {
    final json = await _get(
      '/devices/$deviceId/locations'
      '?from=${from.millisecondsSinceEpoch}&to=${to.millisecondsSinceEpoch}&limit=$limit',
    );
    return ((json['points'] as List?) ?? const [])
        .map((e) => LocPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DeviceSettings> updateSettings(
    String deviceId, {
    String? mode,
    int? normalIntervalSec,
    int? lostIntervalSec,
    bool? fenceEnabled,
  }) async {
    final json = await _put('/devices/$deviceId/settings', {
      if (mode != null) 'mode': mode,
      if (normalIntervalSec != null) 'normalIntervalSec': normalIntervalSec,
      if (lostIntervalSec != null) 'lostIntervalSec': lostIntervalSec,
      if (fenceEnabled != null) 'fenceEnabled': fenceEnabled,
    });
    return DeviceSettings.fromJson(json['settings'] as Map<String, dynamic>);
  }

  Future<Geofence?> getFence(String deviceId) async {
    final json = await _get('/devices/$deviceId/geofence');
    final fence = json['fence'];
    return fence == null ? null : Geofence.fromJson(fence as Map<String, dynamic>);
  }

  Future<Geofence?> saveCircleFence(
    String deviceId, {
    required double centerLat,
    required double centerLng,
    required double radiusM,
    String name = '家',
    bool enabled = true,
  }) async {
    final json = await _put('/devices/$deviceId/geofence', {
      'type': 'circle',
      'name': name,
      'centerLat': centerLat,
      'centerLng': centerLng,
      'radiusM': radiusM,
      'enabled': enabled,
    });
    final fence = json['fence'];
    return fence == null ? null : Geofence.fromJson(fence as Map<String, dynamic>);
  }

  // ── 告警 ────────────────────────────────────────────────────────────────
  Future<({List<AlertItem> alerts, int unreadTotal})> listAlerts({
    String? deviceId,
    bool onlyUnread = false,
    int limit = 50,
  }) async {
    final q = StringBuffer('?limit=$limit');
    if (deviceId != null) q.write('&deviceId=$deviceId');
    if (onlyUnread) q.write('&onlyUnread=true');

    final json = await _get('/alerts$q');
    final alerts = ((json['alerts'] as List?) ?? const [])
        .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return (alerts: alerts, unreadTotal: (json['unreadTotal'] as num?)?.toInt() ?? 0);
  }

  Future<void> markAlertsRead({List<int>? ids, bool all = false, String? deviceId}) async {
    await _put('/alerts/read', {
      if (all) 'all': true,
      if (ids != null) 'ids': ids,
      if (deviceId != null) 'deviceId': deviceId,
    });
  }

  // ── 内部 ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _get(String path) =>
      _send(() => http.get(Uri.parse('$_base$path'), headers: _headers));

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) => _send(
        () => http.post(Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) => _send(
        () => http.put(Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    late http.Response resp;
    try {
      resp = await call().timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ApiException(0, 'NETWORK', '网络请求失败：$e');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(resp.statusCode, 'BAD_RESPONSE', '服务端返回格式异常');
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) return json;

    final err = json['error'] as Map<String, dynamic>?;
    throw ApiException(
      resp.statusCode,
      err?['code'] as String? ?? 'ERROR',
      err?['message'] as String? ?? '请求失败（${resp.statusCode}）',
    );
  }
}
