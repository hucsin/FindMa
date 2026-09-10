import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/models.dart';

const _kToken = 'findma_token';
const _kUsername = 'findma_username';

/// 全局单例 API 客户端
final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// 登录态：null = 未登录
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiProvider));
});

class AuthState {
  final bool loading;
  final String? username;
  final bool loggedIn;

  const AuthState({this.loading = false, this.username, this.loggedIn = false});

  AuthState copyWith({bool? loading, String? username, bool? loggedIn}) => AuthState(
        loading: loading ?? this.loading,
        username: username ?? this.username,
        loggedIn: loggedIn ?? this.loggedIn,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api) : super(const AuthState()) {
    _restore();
  }

  final ApiClient _api;

  /// 启动时恢复本地登录态（token 有效期内免登录）
  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString(_kToken);
    if (token == null || token.isEmpty) {
      state = const AuthState(loggedIn: false);
      return;
    }
    _api.setToken(token);
    state = AuthState(loggedIn: true, username: sp.getString(_kUsername));
    // 清理消费端缓存
    _invalidateData();
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(loading: true);
    try {
      final res = await _api.login(username, password);
      await _persist(res);
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> register(String username, String password) async {
    state = state.copyWith(loading: true);
    try {
      final res = await _api.register(username, password);
      await _persist(res);
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kUsername);
    _api.setToken(null);
    state = const AuthState(loggedIn: false);
    _invalidateData();
  }

  Future<void> _persist(AuthResult res) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kToken, res.token);
    await sp.setString(_kUsername, res.user.username);
    _api.setToken(res.token);
    state = AuthState(loggedIn: true, username: res.user.username);
    _invalidateData();
  }

  void _invalidateData() {
    // 登录态变化后清掉依赖登录数据的缓存，避免展示上一个账号的数据
    _container?.invalidate(devicesProvider);
    _container?.invalidate(alertsProvider);
  }

  /// 由 main.dart 在 ProviderScope 创建后注入容器
  static ProviderContainer? _container;
  static void attach(ProviderContainer c) => _container = c;
}

/// 老人列表（多老人，DESIGN 8.1）
final devicesProvider = FutureProvider<List<DeviceSummary>>((ref) async {
  final api = ref.watch(apiProvider);
  final loggedIn = ref.watch(authProvider).loggedIn;
  if (!loggedIn) return const [];
  return api.listDevices();
});

/// 某个老人的最新摘要
final deviceSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, deviceId) async {
  final api = ref.watch(apiProvider);
  return api.summary(deviceId);
});

/// 告警列表 + 未读总数
final alertsProvider = FutureProvider<({List<AlertItem> alerts, int unreadTotal})>((ref) async {
  final api = ref.watch(apiProvider);
  final loggedIn = ref.watch(authProvider).loggedIn;
  if (!loggedIn) return (alerts: <AlertItem>[], unreadTotal: 0);
  return api.listAlerts();
});

/// 当前选中的老人（地图首页顶部切换用）
final selectedDeviceProvider = StateProvider<String?>((ref) => null);

// ── 头像本地压缩（128×128 JPEG，DESIGN 5.4）─────────────────────────────────
/// 把已压缩的字节编码成服务端要求的 base64（不带 data URL 前缀）
String encodeAvatar(List<int> jpegBytes) => base64Encode(jpegBytes);
