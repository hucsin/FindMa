# guardian-app · FindMa 子女端

Flutter 3（Android + iOS）。地图用 MapLibre GL + 天地图栅格瓦片。

## 目录

```
lib/
├── main.dart                 # ProviderScope + 登录态路由
├── app_config.dart           # API_BASE / 天地图 Key / 轮询间隔
├── api/api_client.dart       # 全部 HTTP 接口
├── models/models.dart
├── state/providers.dart      # Riverpod：登录态 / 老人列表 / 摘要 / 告警
├── map/tdt.dart              # 天地图 style + GeoJSON 工具（圆→多边形、折线、点）
├── update/updater.dart       # 应用内更新：权限检查 + 流式下载（带进度）
├── widgets/
│   ├── avatar_view.dart      # 头像展示 + 拍摄/选取 + 128px 压缩
│   └── update_card.dart      # 设置页的「软件更新」卡片
└── pages/
    ├── login_page.dart
    ├── device_list_page.dart # 多老人卡片列表 + 未读红点
    ├── bind_page.dart        # 扫码绑定（识别 FINDMA-BIND: 前缀）+ 称呼/头像
    ├── device_detail_page.dart # 地图首页：实时位置 + 围栏叠加 + 模式切换
    ├── track_page.dart       # 轨迹回放（今天/昨天/近7天）
    ├── fence_page.dart       # 地图长按选圆心 + 半径滑块
    ├── alerts_page.dart      # 告警中心
    ├── profile_page.dart     # 头像（设备级）/ 称呼（用户级）/ 解绑
    └── settings_page.dart    # 上报频率、数据保留期、关于、软件更新、退出登录
```

## 运行

依赖：Flutter 3.29+（本机验证于 3.47.3）、JDK 21、Android SDK（platform 36、build-tools 36）。
`android/` 平台目录已由 `flutter create` 生成并提交；`local.properties` 指向本机 Flutter 与 SDK 路径。

```bash
flutter pub get
flutter analyze                 # 当前零问题
flutter build apk --debug       # 产物：build/app/outputs/flutter-apk/app-debug.apk

# 联调时才需要覆盖域名（默认已指向 https://findma.izao.cc/api/v1）
flutter run \
  --dart-define=API_BASE=http://10.0.2.2:8791/api/v1 \
  --dart-define=TDT_KEY=<天地图Key>
```

## 应用内更新

设置 →「软件更新」→「下载并安装新版本」：

1. 先检查「安装未知应用」权限；未授权则跳到系统授权页，**返回后自动接着下载**
2. 从 `AppConfig.updateUrl`（默认 `https://dl.izao.cc/guardian.apk`）流式下载，
   按钮下方显示进度条 + 百分比 + 已下载/总大小
3. 下载先写 `.part` 再改名，避免断网留下半包
4. 完成后通过 `FileProvider`（`content://`）拉起系统安装器

原生能力在 `android/.../MainActivity.kt` 的 MethodChannel `findma/updater`，
**没有引入 `permission_handler` / `open_filex` 等插件** —— 三个动作合计不到 80 行，
自实现更可控，也避免插件与 Flutter / AGP 版本互相卡住。

> 把 APK 放到 `dl.izao.cc` 后，`pubspec.yaml` 的 `version` 记得 +1，否则系统会拒绝覆盖安装。

## 要点

- **天地图 Key** 申请"浏览器端"类型，且**不要配置 Referer 白名单**（App 内请求瓦片没有 Referer）。
- 瓦片地址形如 `https://t{0-7}.tianditu.gov.cn/DataServer?T=vec_w&x={x}&y={y}&l={z}&tk=<KEY>`；
  MapLibre 不支持 Leaflet 的 `{s}` 子域占位符，所以 `map/tdt.dart` 里显式展开了 t0~t7。
- 卫星图切换：把 `tdtStyleJson(satellite: true)` 即可（`img_w` + `cia_w`）。
- 天地图是 CGCS2000，与 GPS 的 WGS-84 差厘米级，**全链路零坐标转换**。

## 与 Worker 的约定

- 所有请求带 `Authorization: Bearer <JWT>`；401 时应回到登录页
- 围栏是「每设备一个」（MVP）：`PUT /geofence` 会先删后插
- 配置类操作响应里带 `syncState`：`pending` 表示子女端已改、老人端还没拉取
- 地图首页 30s 轮询一次 `summary`（DESIGN 8.2 的 MVP 方案，阶段二接极光推送）

## 已知待办

- 已编译通过（`flutter analyze` 零问题、`build apk --debug` 成功），但**未在真机/模拟器上跑通**登录 → 绑定 → 地图链路
- `maplibre_gl` 已由 0.20.0 升至 **0.27.0**：0.20.x 仍在用 Flutter 3.29 已移除的
  `PluginRegistry.Registrar`（v1 embedding），在 3.47 上无法编译
- AGP 9 下 `maplibre_gl` 的 `kotlin{}` 扩展缺失，已在 `android/settings.gradle.kts`
  里为该项目单独补 KGP（详见根 README「国内网络」一节下方的说明）
- `removeSource / addGeoJsonSource` 的行为在不同版本略有差异，
  `device_detail_page.dart` 里统一包了 `_safe()` 容错；若你用的版本 API 不符，
  可把整页换成 `flutter_map`（栅格瓦片同样直接可用，改一个文件即可）
- 多边形围栏编辑、头像正方形裁剪 UI、后台 WorkManager 拉取告警尚未实现
