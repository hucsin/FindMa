/// 全局配置
class AppConfig {
  /// 部署 Worker 时绑定的自定义域名（DESIGN 6.1 / 11：必须绑自定义域名）。
  /// 未绑定域名前可用 `flutter run --dart-define=API_BASE=http://10.0.2.2:8791/api/v1` 联调。
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://findma.example.com/api/v1',
  );

  /// 天地图 Key（个人开发者实名注册申请，浏览器端类型、不配 Referer 白名单，DESIGN 4.2）
  static const String tdtKey = String.fromEnvironment(
    'TDT_KEY',
    defaultValue: 'REPLACE_WITH_TIANDITU_KEY',
  );

  /// 前台告警轮询间隔（DESIGN 8.2）
  static const Duration alertPollInterval = Duration(seconds: 30);

  /// 后台补充轮询间隔
  static const Duration backgroundPollInterval = Duration(minutes: 15);

  /// 绑定二维码内容前缀（DESIGN 5.4）
  static const String bindPrefix = 'FINDMA-BIND:';
}
