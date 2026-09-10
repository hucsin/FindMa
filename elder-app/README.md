# elder-app · FindMa 老人端

Android 原生（Kotlin，minSdk 26 / targetSdk 34）。不依赖 GMS，兼容国产 ROM。

## 目录

```
app/src/main/java/com/findma/elder/
├── ElderApp.kt                       # Application：创建前台服务通知渠道
├── Prefs.kt                          # 本地持久化（token 只存手机本地）
├── model/Models.kt
├── service/
│   ├── ElderCoreService.kt           # 常驻前台服务：调度/定位/上报总入口
│   └── NetworkGuardVpnService.kt     # VPN 流量守护
├── location/LocationProvider.kt      # 定位策略（缓存优先 / GPS→NETWORK / LOST 强制高精度）
├── report/
│   ├── ReportScheduler.kt            # AlarmManager 精确调度 + WorkManager 兜底
│   ├── ReportAlarmReceiver.kt
│   ├── ReportWorker.kt
│   └── OfflineQueue.kt               # 离线队列（最多 50 点，成功才清空）
├── config/ConfigSync.kt              # 服务端配置幂等应用
├── net/
│   ├── ApiClient.kt                  # OkHttp HTTPS 上报
│   ├── NetworkMonitor.kt             # WiFi / 蜂窝监听
│   └── Battery.kt
├── boot/BootReceiver.kt              # 开机 / 应用更新后恢复守护
├── update/UpdateManager.kt           # 应用内更新：下载 APK + 拉起系统安装器
└── ui/
    ├── MainActivity.kt               # 状态页 + 绑定二维码 + 各项授权入口
    ├── KeepAliveActivity.kt          # 保活设置引导
    ├── SettingsActivity.kt           # 设置页：软件更新（带下载进度）
    └── QrUtil.kt                     # ZXing 本地渲染二维码
```

## 编译

```bash
# 首次需要 wrapper（仓库未附 jar）
gradle wrapper --gradle-version 8.4

# 或用 Android Studio 打开 elder-app/ 直接同步
```

域名与更新地址在 `app/build.gradle.kts`（已指向生产环境）：

```kotlin
buildConfigField("String", "API_BASE",   "\"https://findma.izao.cc/api/v1\"")
buildConfigField("String", "UPDATE_URL", "\"https://dl.izao.cc/elder.apk\"")
```

## 应用内更新

状态页 →「设置」→「下载并安装新版本」：

1. 先检查「安装未知应用」权限（Android 8.0+ 的**特殊权限**，不是运行时权限，
   只能在系统设置里手动开）；未授权则跳到系统的授权页，**返回后自动接着下载**
2. 从 `UPDATE_URL` 流式下载，按钮下方实时显示进度条 + 百分比 + 已下载/总大小
3. 下载先写 `.part` 再改名，避免断网留下半包被当成完整 APK 安装
4. 完成后通过 `FileProvider`（`content://`）拉起系统安装器

> 把 APK 放到 `dl.izao.cc` 后，`versionCode` 记得比线上 +1，否则系统会拒绝覆盖安装。

## 图标

自适应图标（`res/mipmap-anydpi-v26/`，minSdk 26 起所有设备都支持）：
渐变蓝底 + 白色定位针，针头用 `fillType="evenOdd"` 挖出心形（守护含义）。
带 `<monochrome>` 层，Android 13+ 的「主题图标」也能正确着色。

## 运行时要做的授权（状态页会依次引导）

1. 定位权限 → 2. 后台定位 → 3. 通知权限 → 4. 精确定时 `SCHEDULE_EXACT_ALARM`
   → 5. 电池优化白名单 → 6. VPN 授权（蜂窝网络下才会弹）

缺任意一项都不会崩，只是能力降级：
- 没有精确定时 → 自动降级为 `setAndAllowWhileIdle` + WorkManager(15min) 兜底
- 没有 VPN 授权 → 其他 App 在蜂窝下仍可联网，Worker 会生成 `GUARD_OFF` 告警提醒子女

## 状态页

- 运行状态 / 上报间隔 / 下次上报倒计时 / 最后成功时间
- 网络、流量守护是否生效、电量、待补传点位数、最近异常
- **绑定二维码**（内容 `FINDMA-BIND:<bindCode>`）+ 大字号明文绑定码
- 「重置绑定码」需**长按**（防误触），旧码立即作废
- 「设置」按钮 → 设置页（软件更新）

## 与 Worker 的约定

- 上报体固定带 `settingsVer`（本地已应用的配置版本）、`netType`、`vpnActive`
- 响应里的 `settings` 一律覆盖式应用（幂等），然后用 `reportIntervalSec` 重设下次闹钟
- 上报失败：点位留在离线队列，退避 2min 起、翻倍、上限 15min

## 已知待办

- 多边形围栏绘制未实现（Worker 侧已支持）
- 保活引导页的 ROM 文案需要按实测机型补充验证
- 更新功能尚未在真机验证（需要 `dl.izao.cc` 上先有 `elder.apk`）
