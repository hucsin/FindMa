# FindMa · 老人防丢系统

针对精神疾病老人走失风险的三端防护系统。设计方案见 [`DESIGN.md`](./DESIGN.md)。

```
FindMa/
├── DESIGN.md        # 软件设计方案（v0.3）
├── worker/          # 云端：Cloudflare Workers + TypeScript + Hono + D1   ← 已完整实现
├── elder-app/       # 老人端：Android / Kotlin（常驻服务 + 定位上报 + VPN 流量守护）
└── guardian-app/    # 子女端：Flutter（地图 + 多老人管理 + 围栏 + 告警）
```

## 当前进度

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | Worker 基础（建表 / 注册 / 绑定码 / 上报 / 查询 / 设置 / 扫码绑定 / Cron） | ✅ 完整实现，本地联调全通过 |
| M4 | 围栏算法 + 告警生成 + 失联检测（Worker 侧） | ✅ 完整实现，已用 curl 验证越界/低电/失联/恢复 |
| M2 | 老人端上报链路（前台服务 / 定位 / 调度 / 离线补传 / 绑定二维码 / VPN 守护） | ✅ 已编译通过（APK 4.3 MB），待真机联调 |
| M3 | 子女端基础（登录 / 扫码绑定 / 多老人列表 / 地图 / 模式切换） | ✅ 已编译通过（`flutter analyze` 零问题），待真机联调 |
| M6 | 历史轨迹回放（含服务端抽稀） | 🟡 服务端已完成，子女端页面已就位 |

## 快速开始

### 1. 云端（先在本地跑通，再部署）

```bash
cd worker
npm install

# 创建 D1 数据库，把返回的 database_id 回填到 wrangler.toml
npm run db:create

# 本地建表 + 本地联调（不需要 Cloudflare 账号也能跑）
npm run db:init:local
npm run dev
```

另开一个终端跑端到端用例（会自动注册设备、绑定、上报、越界、低电、失联、恢复）：

```bash
cd worker
bash scripts/smoke.sh
```

部署（已接入 **Workers Builds**：推送 `main` 会自动部署，也可以手动跑）：

```bash
cd worker
npm run db:init:remote        # ① 远端建表（只影响云端，--local 才是本地）
npm run secret:jwt            # ② 写入 JWT_SECRET（不要写进 wrangler.toml）
npm run deploy                # ③ 手动部署（CI 会自动执行这一步）
```

> ⚠️ **`wrangler.toml` 里有两处必须与线上一致，否则 CI 直接失败**：
> - `name = "findma"` —— Workers Builds 侧固定的 Worker 名，不一致时 CI 会覆盖它并尝试自动提 PR
> - `database_id` —— 必须是 D1 的真实 UUID，留占位符会报
>   `binding DB of type d1 must have a valid database_id [code: 10021]`
>   用 `npx wrangler d1 list` 查已有库的 uuid。
>
> ⚠️ **必须绑定自定义域名**（DESIGN 11 章）：`*.workers.dev` 在大陆访问不稳定。
> 在 Cloudflare Dashboard → Workers → findma → Settings → Domains & Routes 添加。
>
> 详细的部署步骤与常见报错见 [`worker/README.md`](worker/README.md#部署到-cloudflare)。

### 2. 老人端（Android）

```bash
cd elder-app
./gradlew assembleDebug
# 产物：app/build/outputs/apk/debug/app-debug.apk（约 4.3 MB）
```

依赖：JDK 17 + Android SDK（platform 34、build-tools 34/35/36）。
Gradle Wrapper（8.4）已随仓库提供；`local.properties` 由 Android Studio 或本地脚本生成
（内容为 `sdk.dir=/path/to/Android/sdk`）。

改 `app/build.gradle.kts` 里的 `API_BASE` 为你部署的域名，然后编译安装到老人手机。
首次打开按状态页指引依次完成：定位权限 → 后台定位 → 通知权限 → 精确定时 → 电池白名单 → VPN 授权。

### 3. 子女端（Flutter）

```bash
cd guardian-app
flutter pub get

flutter build apk --debug
# 产物：build/app/outputs/flutter-apk/app-debug.apk

# 联调（Android 模拟器访问宿主机用 10.0.2.2）
flutter run \
  --dart-define=API_BASE=http://10.0.2.2:8791/api/v1 \
  --dart-define=TDT_KEY=你在天地图申请到的Key
```

依赖：Flutter 3.29+（本仓库在 3.47.3 上验证）、JDK 21、Android SDK（platform 36、build-tools 36）。
`android/` 平台目录由 `flutter create` 生成，已随仓库提交。

真机/发布时把 `API_BASE` 指向已绑定域名的 Worker。

## 国内网络：首次构建的两个大坑

国内直连官方源构建 Android 工程多半会卡在下载上，本仓库已按下表处理，换机器时可复用：

| 卡点 | 现象 | 处理 |
|---|---|---|
| Gradle 发行包 | `gradlew` 卡在 `services.gradle.org`（100+ MB，实测近乎停滞） | 用腾讯镜像预填缓存：`curl -L -o ~/.gradle/wrapper/dists/gradle-<ver>/<hash>/gradle-<ver>-bin.zip https://mirrors.cloud.tencent.com/gradle/gradle-<ver>-bin.zip`，`<hash>` 是 distributionUrl 的 MD5-Base36（先让 wrapper 建好目录即可看到） |
| Maven 依赖 | `maven.google.com` / `repo1.maven.org` 速度时好时坏 | 依赖体量大时，可在 `settings.gradle.kts` 里把阿里云镜像 `https://maven.aliyun.com/repository/google`、`.../public` 放到 `google()`/`mavenCentral()` 之前 |

另外 `maplibre_gl` 需要 NDK `28.2.13676358`（数百 MB），缺失时 AGP 会自动下载。

## 关于「D2」

`DESIGN.md` 中写的 **Cloudflare D2** 是笔误，本项目按 Cloudflare 官方产品 **D1（SQLite）** 实现，
绑定名仍为 `DB`，与文档 6.3 节的表结构一一对应（另新增 `device_state` 表用于围栏状态机与告警去重）。

## 已实现的关键设计点

- **模式切换**（§5.2）：子女端 `PUT /settings` → `settings_ver+1`；老人端下次上报时响应携带最新配置，本地幂等应用后回传 `syncedVer`，子女端可显示「待设备同步 / 已生效」。
- **围栏计算在 Worker**（§6.4）：精度门槛 150m + 缓冲带 50m + 状态翻转才告警，老人手机零负担。
- **离线补传**（§7.2）：老人端本地最多缓存 50 个点，网络恢复后随下次上报批量提交；失败退避 2min 起、上限 15min。
- **流量管控**（§7.3）：蜂窝网络下建立 VpnService 并丢弃所有 tun 数据包，`addDisallowedApplication` 把 FindMa 自身排除在外。
- **零坐标转换**（§4.4）：天地图 CGCS2000 ≈ GPS WGS-84，全链路不做转换。

## 已知待办 / 与文档的差异

| 项 | 说明 |
|---|---|
| 真机联调未做 | 两端已在本机编译通过（老人端：Gradle 8.4 + JDK 17；子女端：Flutter 3.47.3 + AGP 9.1.0 + JDK 21），但尚未在真机/模拟器上跑通完整链路 |
| `maplibre_gl` 与 AGP 9 的 Kotlin 冲突 | Flutter 模板设 `android.builtInKotlin=false`（仍旧走 KGP），而 maplibre_gl 0.27.0 在 AGP ≥ 9 时假设由 AGP 提供 `kotlin{}` 扩展 → 已在 `android/settings.gradle.kts` 里为该项目单独补 KGP。Flutter 会打印 KGP 弃用警告（`flutter_image_compress_common`、`mobile_scanner` 同样命中），待插件迁移 Built-in Kotlin 后可删除该补丁 |
| 重复点入库 | 上报成功但响应丢失时会重传，`locations` 可能产生少量重复行（不影响围栏状态机，轨迹抽稀后视觉无感）。如需彻底去重，可加 `(device_id, dev_ts, lat, lng)` 唯一索引 |
| 多边形围栏绘制 | Worker 与 API 已支持 `polygon`，子女端页面目前只提供「圆形围栏」编辑器 |
| 解绑 | 已提供 `DELETE /devices/:id/bind`，但老人端不会收到通知（需新增推送才能让设备感知） |
| 推送 | 按 §4.3 MVP 方案：前台 30s 轮询 + 后台 WorkManager 15min，未接极光 |
| 头像裁剪 | 目前是等比压缩到 ~128px，不是正方形裁剪，建议后续加一个裁剪 UI |
