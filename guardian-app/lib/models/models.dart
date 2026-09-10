import 'dart:convert';

/// ── 登录 / 注册 ────────────────────────────────────────────────────────────
class AuthUser {
  final String id;
  final String username;
  const AuthUser({required this.id, required this.username});

  factory AuthUser.fromJson(Map<String, dynamic> j) =>
      AuthUser(id: j['id'] as String, username: j['username'] as String);
}

class AuthResult {
  final String token;
  final AuthUser user;
  const AuthResult({required this.token, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        token: j['token'] as String,
        user: AuthUser.fromJson(j['user'] as Map<String, dynamic>),
      );
}

/// ── 设备配置 ───────────────────────────────────────────────────────────────
class DeviceSettings {
  final String mode; // NORMAL | WATCH | LOST
  final int normalIntervalSec;
  final int lostIntervalSec;
  final bool fenceEnabled;
  final int reportIntervalSec;
  final int settingsVer;
  final int syncedVer;
  final String syncState; // synced | pending

  const DeviceSettings({
    required this.mode,
    required this.normalIntervalSec,
    required this.lostIntervalSec,
    required this.fenceEnabled,
    required this.reportIntervalSec,
    required this.settingsVer,
    required this.syncedVer,
    required this.syncState,
  });

  factory DeviceSettings.fromJson(Map<String, dynamic> j) => DeviceSettings(
        mode: j['mode'] as String? ?? 'NORMAL',
        normalIntervalSec: (j['normalIntervalSec'] as num?)?.toInt() ?? 1200,
        lostIntervalSec: (j['lostIntervalSec'] as num?)?.toInt() ?? 60,
        fenceEnabled: j['fenceEnabled'] as bool? ?? true,
        reportIntervalSec: (j['reportIntervalSec'] as num?)?.toInt() ?? 1200,
        settingsVer: (j['settingsVer'] as num?)?.toInt() ?? 1,
        syncedVer: (j['syncedVer'] as num?)?.toInt() ?? 1,
        syncState: j['syncState'] as String? ?? 'synced',
      );

  /// 人话版模式名
  String get modeLabel => switch (mode) {
        'LOST' => '丢失',
        'WATCH' => '关注',
        _ => '普通',
      };
}

/// ── 位置 ───────────────────────────────────────────────────────────────────
class LocPoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final double? speed;
  final double? battery;
  final bool? charging;
  final String? provider;
  final bool? inFence;
  final int? devTs;
  final int reportedAt;

  const LocPoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.speed,
    this.battery,
    this.charging,
    this.provider,
    this.inFence,
    this.devTs,
    required this.reportedAt,
  });

  factory LocPoint.fromJson(Map<String, dynamic> j) => LocPoint(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        speed: (j['speed'] as num?)?.toDouble(),
        battery: (j['battery'] as num?)?.toDouble(),
        charging: j['charging'] as bool?,
        provider: j['provider'] as String?,
        inFence: j['inFence'] as bool?,
        devTs: (j['devTs'] as num?)?.toInt(),
        reportedAt: (j['reportedAt'] as num).toInt(),
      );
}

/// ── 设备列表项 / 摘要 ──────────────────────────────────────────────────────
class DeviceSummary {
  final String id;
  final String name;
  final String nickname;
  final String? avatar;
  final int? lastSeenAt;
  final bool online;
  final int unreadAlerts;
  final DeviceSettings settings;
  final LocPoint? lastLocation;

  const DeviceSummary({
    required this.id,
    required this.name,
    required this.nickname,
    required this.avatar,
    required this.lastSeenAt,
    required this.online,
    required this.unreadAlerts,
    required this.settings,
    required this.lastLocation,
  });

  factory DeviceSummary.fromJson(Map<String, dynamic> j) => DeviceSummary(
        id: j['id'] as String,
        name: j['name'] as String? ?? '老人手机',
        nickname: j['nickname'] as String? ?? '老人',
        avatar: j['avatar'] as String?,
        lastSeenAt: (j['lastSeenAt'] as num?)?.toInt(),
        online: j['online'] as bool? ?? false,
        unreadAlerts: (j['unreadAlerts'] as num?)?.toInt() ?? 0,
        settings: DeviceSettings.fromJson(
            (j['settings'] as Map<String, dynamic>?) ?? const {}),
        lastLocation: j['lastLocation'] == null
            ? null
            : LocPoint.fromJson(j['lastLocation'] as Map<String, dynamic>),
      );
}

/// ── 电子围栏 ───────────────────────────────────────────────────────────────
class Geofence {
  final String id;
  final String name;
  final String type; // circle | polygon
  final double? centerLat;
  final double? centerLng;
  final double? radiusM;
  final List<List<double>> polygon;
  final bool enabled;

  const Geofence({
    required this.id,
    required this.name,
    required this.type,
    this.centerLat,
    this.centerLng,
    this.radiusM,
    this.polygon = const [],
    required this.enabled,
  });

  factory Geofence.fromJson(Map<String, dynamic> j) => Geofence(
        id: j['id'] as String,
        name: j['name'] as String? ?? '家',
        type: j['type'] as String? ?? 'circle',
        centerLat: (j['centerLat'] as num?)?.toDouble(),
        centerLng: (j['centerLng'] as num?)?.toDouble(),
        radiusM: (j['radiusM'] as num?)?.toDouble(),
        polygon: ((j['polygon'] as List?) ?? const [])
            .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
        enabled: j['enabled'] as bool? ?? true,
      );
}

/// ── 告警 ───────────────────────────────────────────────────────────────────
class AlertItem {
  final int id;
  final String deviceId;
  final String? nickname;
  final String? avatar;
  final String type;
  final String title;
  final String body;
  final bool read;
  final int createdAt;

  const AlertItem({
    required this.id,
    required this.deviceId,
    this.nickname,
    this.avatar,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });

  factory AlertItem.fromJson(Map<String, dynamic> j) => AlertItem(
        id: (j['id'] as num).toInt(),
        deviceId: j['deviceId'] as String,
        nickname: j['nickname'] as String?,
        avatar: j['avatar'] as String?,
        type: j['type'] as String,
        title: j['title'] as String? ?? '告警',
        body: j['body'] as String? ?? '',
        read: j['read'] as bool? ?? false,
        createdAt: (j['createdAt'] as num).toInt(),
      );
}

/// 把服务端返回的 base64 头像还原成可解码的 data URL（无前缀时补上）
String? avatarDataUrl(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  if (base64.startsWith('data:')) return base64;
  try {
    // 简单校验：能被 base64 解码才用
    base64Decode(base64);
  } catch (_) {
    return null;
  }
  return 'data:image/jpeg;base64,$base64';
}
