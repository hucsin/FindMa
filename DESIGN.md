# FindMa 老人防丢系统 · 软件设计方案

> 版本：v0.3
> 日期：2026-09-10
> 状态：主要选型已确认（见第 13 章）；v0.3 新增：绑定时配置老人**头像**（设备级共享）与**称呼**（用户级，各子女独立）

---

## 1. 项目背景与目标

针对老人的走失风险。老人已形成"出门必带手机"的机械记忆，以此为前提构建三端防护系统：

| 目标 | 说明 |
|---|---|
| 实时掌握位置 | 老人端定时上报 GPS（默认 20 分钟，可调），子女端随时查看 |
| 电子围栏 | 越界即时提醒子女；**围栏计算放在 Worker 端**，老人手机零负担 |
| 丢失模式 | 走失时切换高频上报（频率由子女端设置），快速定位 |
| 关注模式 | 围栏生效，越界/回归均提醒子女 |
| 流量管控 | 有 WiFi 时全部 App 可联网；无 WiFi 时**仅 FindMa 可联网**（VpnService 实现），节省老人手机流量 |
| 历史轨迹 | 子女端按时间区间查询，在地图上回放老人活动路线 |

## 2. 总体架构

```
┌─────────────────┐    HTTPS 定时上报(默认20min)    ┌──────────────────────────┐
│   老人端 App     │ ─────────────────────────────→ │    Cloudflare Worker      │
│  (Android/Kotlin)│ ←───────────────────────────── │  (TypeScript + Hono)      │
│                 │     响应携带最新配置/模式指令      │        │                 │
│ · 常驻前台服务    │                                │        ▼                 │
│ · 定位+定时上报   │                                │   Cloudflare D2 数据库     │
│ · VPN网络守护    │                                │  (位置/围栏/告警/配置)      │
└─────────────────┘                                └──────────┬───────────────┘
                                                              │ 轮询/查询 + 设置下发
                                                              ▼
                                                   ┌──────────────────────────┐
                                                   │     子女端 App (Flutter)   │
                                                   │ · 多老人管理 + 扫码绑定     │
                                                   │ · 地图查看实时/历史位置     │
                                                   │ · 设置模式/上报频率/围栏    │
                                                   │ · 告警中心(越界/低电/失联)  │
                                                   └──────────────────────────┘
```

**三端职责划分：**

| 端 | 目录名 | 职责 |
|---|---|---|
| 老人端 | `elder-app/` | 常驻后台、定位、定时上报、离线补传、应用服务端下发的配置、VPN 流量管控 |
| 云端 | `worker/` | 接收上报入库（D2）、下发配置/模式指令、**电子围栏计算**、越界/低电/失联告警、定时清理任务 |
| 子女端 | `guardian-app/` | **管理多个老人设备**、扫码绑定、查看实时位置/历史轨迹（地图）、设置模式/上报频率/电子围栏、接收告警 |

## 3. 工程目录结构

```
FindMa/
├── DESIGN.md            # 本方案文档
├── elder-app/           # 老人端（Android / Kotlin）
├── worker/              # 云端（Cloudflare Worker / TypeScript + D2）
└── guardian-app/        # 子女端（Flutter，支持 Android/iOS）
```

## 4. 技术选型

### 4.1 选型总表

| 端 | 技术栈 | 说明 |
|---|---|---|
| 老人端 | Kotlin + Android 原生（minSdk 26 / Android 8.0+，targetSdk 34） | VpnService、前台服务、精确闹钟均为深度系统能力，原生实现最可靠；不依赖 GMS，兼容国产 ROM |
| 云端 | Cloudflare Workers + TypeScript + Hono 框架 + D2 | Hono 是 Workers 官方生态最流行的轻量路由框架；Cron Triggers 做定时任务 |
| 子女端 | Flutter 3（Dart）+ maplibre_gl + 天地图瓦片 | 一套代码双端（Android/iOS）；地图方案见 4.2 |

### 4.2 地图方案（已确认）：MapLibre + 天地图瓦片

子女端使用 `maplibre_gl`（开源渲染引擎，Flutter 插件）加载天地图栅格瓦片：

| 项 | 说明 |
|---|---|
| 渲染引擎 | MapLibre GL（Mapbox GL 开源分支，零授权费用），Flutter 插件 `maplibre_gl` |
| 瓦片源 | 天地图（国家地理信息公共服务平台）：`vec_w` 矢量底图 + `cva_w` 中文注记叠加；`img_w` 卫星影像可切换 |
| 费用 | 免费（天地图个人开发者实名注册申请 Key） |
| 坐标系 | 天地图瓦片为 **CGCS2000**，与 GPS 原生 WGS-84 差异为厘米级，工程上直接忽略 → **全链路零坐标转换** |
| 国内访问 | 政务 CDN，国内访问快且稳定 |

瓦片 URL 形如：`https://t{0-7}.tianditu.gov.cn/DataServer?T=vec_w&x={x}&y={y}&l={z}&tk=<KEY>`（注记层 `cva_w` 叠加在底图之上，卫星图组合用 `img_w` + `cia_w`）。

相比弃选方案：高德（数据最全但 GCJ-02 需双向坐标转换）、OSM（免 Key 但国内瓦片慢、乡镇数据粗）。天地图 + MapLibre 兼得"国内访问快 + 完全免费 + 零坐标转换"。

注意事项：
- 天地图 Key 申请"浏览器端"类型，且**不配置 Referer 白名单**（App 内直接请求瓦片无 Referer）；
- 个人 Key 有日调用量限制，但本系统地图仅在子女端打开时加载，用量远低于限额。

### 4.3 消息推送选型（重点）

需求：老人越界/低电/失联时，子女端要收到提醒。**国产 Android 无 GMS，FCM 不可用；且后台常驻推送在国产 ROM 上会被限制。**

| 方案 | 费用 | 实时性 | 结论 |
|---|---|---|---|
| 站内告警 + 轮询（MVP 采用） | 0 | 前台 30s / 后台 15min | 无三方依赖，全链路可控 |
| 极光推送 JPush（阶段二可选） | 免费版（1000 设备内） | 秒级（厂商通道，国产 ROM 后台可达） | 需要即时后台提醒时接入 |
| FCM | 免费 | 秒级 | 大陆不可用，仅海外场景 |

**已确认：MVP 用"告警中心 + 轮询"，阶段二按需接极光。** 即：告警先进 Worker 的 `alerts` 表，子女端打开时轮询（30s）、后台 WorkManager 定时拉取（15min）+ 本地通知。

### 4.4 坐标系处理（已简化）

天地图瓦片坐标系（CGCS2000）与 GPS 原生输出（WGS-84）差异为厘米级，工程上直接忽略，**全链路零坐标转换**：

```
GPS 芯片(WGS-84) → D2 存储(WGS-84) → Worker 围栏计算(WGS-84) → 子女端展示(天地图 CGCS2000≈WGS-84)
```

若未来切换高德地图，再引入 WGS-84 ↔ GCJ-02 转换模块即可（公开算法约 30 行代码）。

---

## 5. 业务模式设计

### 5.1 模式定义

| 模式 | 上报频率 | 围栏告警 | 场景 |
|---|---|---|---|
| NORMAL 普通 | `normal_interval_sec`（默认 1200s = 20 分钟，子女端可改） | 不告警（围栏仍在地图可见） | 日常 |
| WATCH 关注 | 同普通频率 | **生效**：越界/回归均提醒 | 日常防护 |
| LOST 丢失 | `lost_interval_sec`（子女端设置，建议 30s~5min） | 生效 | 老人走失，快速定位 |

### 5.2 模式切换流程（按你指定的机制）

```
子女端                      Worker (D2)                   老人端
  │  PUT /settings            │                             │
  │  {mode: LOST,             │  保存配置, settings_ver+1    │
  │   lostIntervalSec: 60}    │  (标记"待设备同步")           │
  ├──────────────────────────→│                             │
  │                           │      下次定时上报(≤当前间隔)  │
  │                           │ ←───────────────────────────┤
  │                           │  响应携带: {mode:LOST,       │
  │                           │   reportIntervalSec:60}     │
  │                           ├───────────────────────────→│
  │                           │                    切换高频调度(60s)
  │                           │                    应用后随下次上报回传 ver
```

- 切换生效延迟 = 最多一个当前上报间隔（普通模式下最长 20 分钟）。
- Worker 返回配置时**始终携带当前生效值**，老人端幂等应用，实现简单可靠。
- 子女端可显示"配置状态：待设备同步 / 已生效"（对比 `settings_ver` 与设备回传的 `synced_ver`）。

### 5.3 老人端调度模型

- 调度器：`AlarmManager.setExactAndAllowWhileIdle`（Doze 下也能触发），每次上报成功后按 Worker 下发的间隔重设下一次闹钟。
- `SCHEDULE_EXACT_ALARM` 权限被拒时降级为 `setAndAllowWhileIdle` + `WorkManager` 兜底。
- 开机自启（`RECEIVE_BOOT_COMPLETED`）恢复调度与 VPN 状态。

### 5.4 设备绑定流程（扫码，已确认）

```
老人端首次启动 ──POST /device/register──→ Worker
                                         生成 deviceId(uuid) + device token
                                         + 唯一绑定码 bindCode（存 D2）
             ←── {deviceId, token, bindCode} ──┘
老人端状态页展示二维码（内容 = FINDMA-BIND:<bindCode>，本地 ZXing 渲染）
子女端"添加老人" → 扫描二维码 → 解析出 bindCode
             → 填写称呼(必填，如"爸爸/爷爷") + 拍照/相册选头像(可选)
             → POST /devices/bind {bindCode, nickname, avatar?}
Worker: 校验 bindCode → 建立 user-device 绑定(记录该子女的称呼)
      → 头像存设备级(所有子女共享) → 返回设备信息
```

- **绑定码由 Worker 生成**（服务端唯一标识，8 位大小写字母+数字、去除易混淆字符），老人端仅负责渲染二维码；
- 二维码内容带 `FINDMA-BIND:` 前缀，子女端识别到该前缀自动进入绑定流程；
- 绑定码长期有效，**多个子女可扫同一个码分别绑定**（各自独立账号）；
- 老人端提供"重置绑定码"（`POST /device/rebind-code`），旧码立即作废，防泄露；
- 扫码不便时，状态页同时展示大字号明文绑定码，子女端支持手动输入；
- **称呼（nickname）为用户级**：存于 `user_devices`，每个子女按自己的叫法命名（如"爸爸"/"爷爷"），互不影响，绑定时必填；
- **头像（avatar）为设备级**：存于 `devices`，所有绑定的子女共享同一张；绑定时可选上传（未上传则用默认头像），后续可在子女端"老人资料"页更换；
- 头像由子女端本地裁剪压缩为 128×128 JPEG（约 10~40KB，base64 上传），Worker 校验大小 ≤100KB。

---

## 6. Worker 端设计（`worker/`）

### 6.1 技术栈

- TypeScript + [Hono](https://hono.dev)（路由/中间件/JWT）
- Cloudflare D2（绑定名 `DB`）、Cron Triggers
- 部署：`wrangler deploy`；**必须绑定自定义域名**（`*.workers.dev` 在大陆访问不稳定，见 11 章）

### 6.2 API 设计（前缀 `/api/v1`，全部 JSON over HTTPS）

**老人端接口（鉴权：请求头 `X-Device-Token`）**

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/device/register` | 首次启动注册（无鉴权），Worker 生成并返回 `{deviceId, token, bindCode}`（bindCode 即二维码内容，见 5.4） |
| POST | `/device/rebind-code` | 重置绑定码（旧二维码立即作废） |
| POST | `/report` | 上报位置（支持多点批量离线补传），响应携带最新配置 |

```json
// POST /report 请求体
{
  "settingsVer": 3,
  "netType": "cellular", "vpnActive": true,
  "appVer": "1.0.0",
  "points": [
    { "lat": 31.2304, "lng": 121.4737, "acc": 12.5, "speed": 1.2, "bearing": 90,
      "batt": 66, "charging": false, "provider": "gps", "devTs": 1757460000000 }
  ]
}
// 响应体
{
  "serverTs": 1757460001000,
  "settings": { "ver": 4, "mode": "LOST", "reportIntervalSec": 60, "fenceEnabled": true }
}
```

**子女端接口（鉴权：`Authorization: Bearer <JWT>`）**

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` / `/auth/login` | 注册/登录，返回 JWT（有效期 30 天） |
| GET | `/devices` | 我的老人设备列表（支持绑定**多个老人**，含称呼、头像、各自最新位置摘要、配置状态、未读告警数） |
| POST | `/devices/bind` | **扫码绑定**：`{bindCode, nickname, avatar?}`（nickname=称呼必填，用户级；avatar=base64 头像可选，设备级共享 ≤100KB）；也支持手动输入明文绑定码 |
| PUT | `/devices/:id/profile` | 修改老人资料：`{nickname}`（当前用户视角的称呼）或 `{avatar}`（设备级共享头像） |
| GET | `/devices/:id/summary` | 最新位置、电量、模式、围栏状态、最后上报时间 |
| GET | `/devices/:id/locations?from&to&limit` | 历史位置（轨迹数据源，服务端可抽稀） |
| PUT | `/devices/:id/settings` | 设置 `{mode, normalIntervalSec, lostIntervalSec, fenceEnabled}` |
| GET/PUT | `/devices/:id/geofence` | 查看/设置电子围栏（圆形或多边形） |
| GET | `/alerts?deviceId&onlyUnread` | 告警列表 |
| PUT | `/alerts/read` | 标记已读（单条/全部） |

### 6.3 D2 数据库设计（核心表）

```sql
-- 子女用户
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,          -- PBKDF2
  created_at INTEGER NOT NULL
);

-- 老人设备
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT DEFAULT '老人手机',
  avatar TEXT,                          -- 头像(base64 JPEG,子女端压缩至~40KB,设备级共享;未来需原图/多图再引入R2)
  token_hash TEXT NOT NULL,             -- SHA-256(device token)，原文只在老人手机本地
  invite_code TEXT UNIQUE NOT NULL,     -- 绑定码(Worker 生成的唯一标识，二维码内容，可重置)
  last_seen_at INTEGER                  -- 冗余最近上报时间
);

-- 设备配置（模式在这里切换）
CREATE TABLE device_settings (
  device_id TEXT PRIMARY KEY,
  mode TEXT NOT NULL DEFAULT 'NORMAL',  -- NORMAL | WATCH | LOST
  normal_interval_sec INTEGER NOT NULL DEFAULT 1200,
  lost_interval_sec INTEGER NOT NULL DEFAULT 60,
  fence_enabled INTEGER NOT NULL DEFAULT 1,
  settings_ver INTEGER NOT NULL DEFAULT 1,   -- 每次修改+1
  synced_ver INTEGER NOT NULL DEFAULT 1,     -- 设备已确认的版本
  updated_at INTEGER NOT NULL
);

-- 位置记录（时间序列）
CREATE TABLE locations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  lat REAL NOT NULL, lng REAL NOT NULL,
  accuracy REAL, speed REAL, bearing REAL,
  battery REAL, charging INTEGER,
  provider TEXT, net_type TEXT, vpn_active INTEGER,
  in_fence INTEGER,                     -- 1在内 0在外 NULL未判定(精度不足)
  dev_ts INTEGER,
  reported_at INTEGER NOT NULL          -- 以服务器接收时间排序（防设备时钟漂移）
);
CREATE INDEX idx_loc_dev_time ON locations(device_id, reported_at);

-- 电子围栏（MVP 每设备一个，表结构天然支持多个）
CREATE TABLE geofences (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  name TEXT DEFAULT '家',
  type TEXT NOT NULL,                   -- circle | polygon
  center_lat REAL, center_lng REAL, radius_m REAL,
  polygon_json TEXT,                    -- [[lat,lng],...]
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
);

-- 用户-设备绑定（支持多个子女）
CREATE TABLE user_devices (
  user_id TEXT NOT NULL, device_id TEXT NOT NULL,
  nickname TEXT NOT NULL,               -- 称呼(用户级,如"爸爸"/"爷爷",各子女独立,绑定时必填)
  role TEXT DEFAULT 'owner', created_at INTEGER,
  PRIMARY KEY (user_id, device_id)
);

-- 告警
CREATE TABLE alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  type TEXT NOT NULL,     -- OUT_OF_FENCE|BACK_IN_FENCE|LOW_BATTERY|OFFLINE|RECOVERED|GUARD_OFF
  title TEXT, body TEXT, payload_json TEXT,
  read INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_alerts_dev_time ON alerts(device_id, created_at);
```

### 6.4 电子围栏计算（在 Worker，不放老人手机）

每次收到上报点，按时间序逐点判定：

1. **精度门槛**：`accuracy > 150m` 的点不参与判定（`in_fence = NULL`，状态保持），防室内漂移误报；
2. **圆形围栏**：Haversine 球面距离 + **缓冲带防抖**（默认 50m）：
   - `d > R + 50m` → 界外；`d < R` → 界内；`R < d ≤ R+50m` → 保持原状态（防边界抖动）；
3. **多边形围栏**：射线法（Ray Casting）判定点在多边形内，同样加缓冲带；
4. **状态翻转才告警**：`in → out` 生成 `OUT_OF_FENCE`，`out → in` 生成 `BACK_IN_FENCE`，仅 WATCH/LOST 模式下产生；
5. 首次上报/围栏修改后第一次判定：直接以该点建立状态（若开启关注模式时人已在外，立即告警）。

### 6.5 告警类型

| 类型 | 触发条件 |
|---|---|
| OUT_OF_FENCE / BACK_IN_FENCE | 围栏状态翻转（WATCH/LOST 模式） |
| LOW_BATTERY | 上报电量 ≤ 20% 且未充电（去重：每次充电周期只告一次） |
| OFFLINE | 超过 `max(3×当前间隔, 2小时)` 未上报（Cron 检查，同一失联事件只告一次） |
| RECOVERED | OFFLINE 后恢复上报 |
| GUARD_OFF | 蜂窝网络下 VPN 守护未生效（`netType=cellular && vpnActive=false`），防流量管控失效 |

### 6.6 Cron 定时任务

| 频率 | 任务 |
|---|---|
| 每小时 | 失联检测（OFFLINE/RECOVERED 判定） |
| 每天 | 清理超过保留期（默认 180 天）的 `locations` 数据 |

### 6.7 免费额度评估（Cloudflare Free 计划）

| 资源 | 免费额度 | 本系统估算（单老人设备） |
|---|---|---|
| Workers 请求 | 10 万次/天 | 普通模式 72 次 + 丢失模式 1440 次/天 + 子女轮询 ≈ 数千次/天，富余 95%+ |
| D2 行读取 | 500 万行/天 | 每次上报/查询涉及行数个位数~百级，富余极大 |
| D2 行写入 | 10 万行/天 | 同上 |
| D2 存储 | 5 GB | 20 分钟间隔约 2.6 万条/年（<10MB/年）；丢失模式 1 分钟 1440 条/天，180 天保留期也在 MB 级 |

**结论：全链路 0 成本运行（唯一硬性支出是一个域名，约 ¥10~60/年）。**

---

## 7. 老人端设计（`elder-app/`，Android / Kotlin）

### 7.1 模块划分

```
elder-app/
└── app/src/main/java/com/findma/elder/
    ├── service/
    │   ├── ElderCoreService.kt      # 常驻前台服务：调度、定位、上报的总入口
    │   └── NetworkGuardVpnService.kt# VPN 网络守护
    ├── location/LocationProvider.kt # 定位策略
    ├── report/
    │   ├── ReportScheduler.kt       # AlarmManager 精确调度
    │   ├── ReportClient.kt          # HTTPS 上报(OkHttp)
    │   └── OfflineQueue.kt          # 离线队列(本地缓存最近50条,网络恢复批量补传)
    ├── config/ConfigSync.kt         # 服务端配置应用(模式/间隔)
    ├── net/NetworkMonitor.kt        # WiFi/蜂窝 监听
    ├── boot/BootReceiver.kt         # 开机恢复
    └── ui/                          # 极简界面(状态页/保活引导)
```

### 7.2 核心机制

**常驻后台（前台服务）**
- `ElderCoreService` 以前台服务运行（常驻通知"防看护运行中"，符合 Android 规范且大幅降低被杀概率）；
- 申请电池优化白名单（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`）；
- 内置"保活设置引导页"：检测主流国产 ROM（小米/华为/OPPO/vivo）并引导用户开启自启动、后台无限制等（国产 ROM 的杀后台无法代码根治，引导 + 前台服务 + 精确闹钟三管齐下是业界通行做法）。

**定位策略**
- 优先使用新鲜缓存（上次定位 < ½ 上报间隔内直接复用）；
- 否则单次定位：GPS 优先（超时 90 秒），NETWORK 定位补充（标注 `provider`）；
- LOST 模式强制高精度 GPS。

**上报与离线补传**
- 上报时连同本地积攒的离线点一起批量上报（`points` 数组），Worker 按时间序逐点入库与判定围栏；
- 上报失败退避重试（+2 分钟起，上限 15 分钟），点位不丢失。

### 7.3 VPN 网络守护（核心需求 4.2 的实现方案）

```
NetworkMonitor 监听 ConnectivityManager:
├── WiFi 已连接 → 停止 VPN → 所有 App 正常联网
└── WiFi 断开(蜂窝) → 启动 NetworkGuardVpnService:
      VpnService.Builder()
        .setSession("FindMa 网络守护")
        .addAddress("10.111.0.1", 24)
        .addRoute("0.0.0.0", 0)                      // 接管全部路由
        .addDisallowedApplication("com.findma.elder") // 本 App 流量不走 VPN
        .establish()
      后台线程持续读取并丢弃 tun 数据包(防缓冲堆积, CPU占用极低)
```

**原理**：除 FindMa 外所有 App 的流量都被路由进 VPN 的 tun 虚拟网卡，我们不转发任何数据包 → 这些 App 的联网请求全部失败（等于"直接拒绝"）；FindMa 自身被排除在 VPN 之外，直接走蜂窝网络正常上报。

**边界处理**
- 首次启用弹出系统 VPN 授权对话框（一次性授权）；
- 与第三方 VPN 冲突时（Android 同时只允许一个 VPN）通知栏提示；
- VPN 状态随上报回传（`vpnActive`），失效时子女端收到 `GUARD_OFF` 告警；
- 开机自动恢复上次的守护状态。

### 7.4 权限清单

| 权限 | 用途 |
|---|---|
| ACCESS_FINE_LOCATION + ACCESS_BACKGROUND_LOCATION | 定位 |
| FOREGROUND_SERVICE(_LOCATION/_SPECIAL_USE) | 前台服务 |
| INTERNET / ACCESS_NETWORK_STATE | 上报与网络监听 |
| RECEIVE_BOOT_COMPLETED | 开机恢复 |
| SCHEDULE_EXACT_ALARM | 精确调度 |
| POST_NOTIFICATIONS | 前台服务常驻通知 |
| REQUEST_IGNORE_BATTERY_OPTIMIZATIONS | 电池白名单 |

### 7.5 界面（极简，老人/安装者使用）

- **状态页**：运行状态、VPN 守护状态、定位/网络/电量、下次上报倒计时、**绑定二维码（Worker 生成的唯一绑定码，本地 ZXing 渲染，下方附大字号明文）+ 重置绑定码入口**；
- **保活引导页**：按 ROM 品牌给出设置指引；
- 主界面无多余操作，防误触（退出需长按确认）。

---

## 8. 子女端设计（`guardian-app/`，Flutter）

技术栈：Flutter 3 + `maplibre_gl` + 天地图瓦片（见 4.2）；状态管理 Riverpod；扫码 `mobile_scanner`；头像拍摄/选取 `image_picker` + 本地裁剪压缩 `flutter_image_compress`（128×128 JPEG）。

### 8.1 页面结构

| 页面 | 功能 |
|---|---|
| 登录/注册 | 用户名密码 |
| 老人列表 | 已绑定的多个老人卡片（**头像 + 称呼**/最新状态摘要/未读告警数），点击进入对应老人的地图首页；右上角"+"**扫码添加新老人**（识别 `FINDMA-BIND:` 前缀自动进入绑定流程，支持手动输入） |
| 绑定引导页（新增） | 扫码/输入绑定码后进入：**填写称呼（必填，如"爸爸/爷爷"）+ 拍照或相册选头像（可选）**→ 本地裁剪压缩 → 提交绑定 |
| 老人资料页（新增） | 查看/修改头像（设备级，全员共享，重新上传同规格压缩）与我的称呼（用户级）；解绑入口 |
| 地图首页 | 当前老人的最新位置（含精度圈）、围栏叠加显示、模式一键切换（普通/关注/**丢失**）、电量与最后上报时间；顶部可快速切换其他老人 |
| 轨迹回放 | 时间区间选择（今天/昨天/近7天/自定义）→ 地图 Polyline + 关键点列表；点位过多时服务端抽稀 |
| 围栏编辑 | 地图选点 + 拖拽半径（圆形）；多边形顶点编辑；启用开关 |
| 告警中心 | 未读红点；越界/回归/低电/失联/守护失效列表，点击查看详情 |
| 设置 | 上报频率（普通间隔 / 丢失间隔）、数据保留期、关于 |

### 8.2 通知机制

- 前台：30 秒轮询 `alerts` + 本地通知；
- 后台：WorkManager 15 分钟拉取 + 本地通知；
- 阶段二（可选）：接入极光推送实现秒级后台提醒（见 4.3）。

---

## 9. 关键流程时序

**① 定时上报（普通流程）**
```
闹钟触发 → 取定位(缓存或单次GPS) → 组包(含离线积攒点)
→ POST /report → Worker: 逐点入库+围栏判定+告警生成
→ 响应{mode, reportIntervalSec} → 应用配置 → 设定下次闹钟
```

**② 越界告警（关注模式）**
```
上报点(d > R+50m, acc ≤ 150m) → Worker: in_fence: 1→0
→ 写入 alert(OUT_OF_FENCE) → 子女端轮询拉到 → 本地通知弹出
```

**③ 丢失模式（见 5.2 时序图）**

**④ 无 WiFi 流量管控**
```
WiFi断开 → NetworkGuardVpnService 启动 → 其他App联网被拒
→ FindMa 直连蜂窝上报(vpnActive=true) → WiFi重连 → VPN停止
```

---

## 10. 安全设计

- 全链路 HTTPS（Workers 默认强制）；
- 老人端：device token 仅存手机本地，D2 只存 SHA-256 哈希；上报接口按 token 鉴权；
- 子女端：密码 PBKDF2 哈希存储；JWT（HS256，secret 存 Worker Secrets）；
- D2 全部使用预编译语句（防注入）；
- 位置数据仅存于自有 D2，不经过任何第三方（除阶段二可选的极光推送）。

---

## 11. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| `*.workers.dev` 大陆访问不稳定 | 系统不可用 | **必须绑定自定义域名**（Cloudflare 托管，国内可达性好）——需你准备一个域名 |
| 国产 ROM 杀后台 | 漏报/失联 | 前台服务 + 电池白名单 + 自启动引导 + 精确闹钟 + OFFLINE 告警兜底；开发期在小米/华为真机实测 |
| GPS 室内漂移 | 围栏误报/漏报 | 精度门槛(150m) + 缓冲带(50m) + 状态翻转才告警 |
| VPN 授权被撤销/冲突 | 流量管控失效 | vpnActive 回传 + GUARD_OFF 告警，子女可远程知晓 |
| 国产 Android 后台推送不可达 | 告警延迟 | MVP 轮询方案已知延迟上限（后台 15min）；阶段二接极光 |
| 老人手机欠费/关机 | 无法定位 | OFFLINE 告警提醒子女；建议业务上保号 + 最低套餐 |
| 设备时钟漂移 | 轨迹乱序 | 统一以服务器接收时间（reported_at）排序 |

---

## 12. 开发里程碑

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| M1 Worker 基础 | D2 建表、设备注册（生成绑定码）/重置绑定码/上报/查询/设置/扫码绑定 API、wrangler 本地联调 | curl 模拟上报→D2 可查、配置可下发、bindCode 可完成绑定 |
| M2 老人端上报链路 | 前台服务、定位、调度、上报、配置同步、离线补传、绑定二维码展示 | 真机 20 分钟自动上报，改配置后下次上报生效，二维码可被子女端识别 |
| M3 子女端基础 | 登录、扫码绑定（含设置称呼+头像）、老人列表（多老人切换）、地图展示最新位置、模式/频率设置 | 手机上完整走通"扫码绑定并配置称呼头像→多老人切换查看→设置" |
| M4 围栏与告警 | 围栏 API+算法、告警生成、子女端告警中心、失联检测 | 模拟越界点→子女端收到告警 |
| M5 VPN 网络守护 | VpnService、网络监听、开机恢复、引导页 | 断 WiFi 后其他 App 断网、FindMa 正常上报 |
| M6 历史轨迹 | 轨迹查询、地图回放、时间区间选择、抽稀 | 按天/区间回放轨迹流畅 |
| M7 打磨 | 低电告警、数据清理 Cron、保活真机适配、异常兜底 | 主流 ROM 真机 24 小时稳定运行 |

---

## 13. 待确认问题清单

| # | 问题 | 结论 |
|---|---|---|
| 1 | 域名 | ✅ 已有域名，部署时 DNS 托管到 Cloudflare 并绑定 Worker |
| 2 | 地图 | ✅ MapLibre + 天地图瓦片（免费，全链路零坐标转换） |
| 3 | 子女端平台 | ✅ Flutter 双端（Android + iOS） |
| 4 | 推送 | ✅ MVP 轮询 + 告警中心，阶段二接极光免费版 |
| 5 | 多老人管理 | ✅ 子女端可绑定并管理多个老人，扫码绑定（Worker 生成唯一绑定码）；绑定时设置老人**头像**（设备级共享）与**称呼**（用户级，各子女独立） |
| 6 | 账号方式 | 暂按用户名密码（免费）执行，如需手机号+短信验证码再提出 |
| 7 | 老人手机 Android 版本 | 暂按 Android 8.0+ 执行（如需兼容更低版本请提出） |
| 8 | 数据保留期 | 暂按 180 天执行（子女端设置页可调） |

---

*主要选型已确认；第 13 章 6~8 项按默认执行（如有异议请提出），确认后即可从 M1（Worker 端）开始开发。*
