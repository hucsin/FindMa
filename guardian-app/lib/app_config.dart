/// 全局配置
class AppConfig {
  /// 已绑定的自定义域名（DESIGN 6.1 / 11：workers.dev 在大陆被 DNS 污染，必须绑域名）。
  /// 联调时可覆盖：`flutter run --dart-define=API_BASE=http://10.0.2.2:8791/api/v1`
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://findma.izao.cc/api/v1',
  );

  /// 天地图 Key（个人开发者实名注册申请，浏览器端类型、不配 Referer 白名单，DESIGN 4.2）
  static const String tdtKey = String.fromEnvironment(
    'TDT_KEY',
    defaultValue: 'REPLACE_WITH_TIANDITU_KEY',
  );

  /// 应用内更新：设置页从这里下载新版本 APK
  static const String updateUrl = String.fromEnvironment(
    'UPDATE_URL',
    defaultValue: 'https://dl.izao.cc/guardian.apk',
  );

  /// 当前版本号，与 pubspec.yaml 的 version 保持一致
  static const String appVersion = '0.1.0';

  /// 前台告警轮询间隔（DESIGN 8.2）
  static const Duration alertPollInterval = Duration(seconds: 30);

  /// 后台补充轮询间隔
  static const Duration backgroundPollInterval = Duration(minutes: 15);

  /// 绑定二维码内容前缀（DESIGN 5.4）
  static const String bindPrefix = 'FINDMA-BIND:';
}
