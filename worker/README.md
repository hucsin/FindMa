# worker · FindMa 云端

Cloudflare Workers + TypeScript + [Hono](https://hono.dev) + D1。

## 目录

```
worker/
├── wrangler.toml          # 绑定 DB / Cron / 业务参数 vars
├── schema.sql             # D1 建表脚本
├── .dev.vars              # 本地开发密钥（已 gitignore）
├── scripts/smoke.sh       # 端到端 curl 用例
└── src/
    ├── index.ts           # Hono 应用装配 + Cron 入口
    ├── types.ts           # Env / 行类型
    ├── config.ts          # 配置与业务约束（LIMITS）
    ├── http.ts            # 统一响应/入参工具
    ├── middleware/
    │   ├── deviceAuth.ts  # X-Device-Token（比对 SHA-256）
    │   └── userAuth.ts    # Authorization: Bearer <JWT>
    ├── routes/
    │   ├── device.ts      # POST /device/register、/device/rebind-code
    │   ├── report.ts      # POST /report
    │   ├── auth.ts        # POST /auth/register、/auth/login
    │   ├── devices.ts     # /devices 全部接口 + 围栏
    │   └── alerts.ts      # /alerts 列表与标记已读
    ├── services/
    │   ├── store.ts       # 配置/状态/围栏/告警/文案 存取
    │   ├── report.ts      # 上报主流程（围栏状态机 + 告警）
    │   └── cron.ts        # 失联检测 + 轨迹清理
    └── utils/
        ├── id.ts          # uuid / device token / 绑定码
        ├── auth.ts        # PBKDF2 / JWT(HS256) / SHA-256
        └── geo.ts         # Haversine / 射线法 / 围栏判定
```

## API 一览（前缀 `/api/v1`）

| 方法 | 路径 | 鉴权 | 说明 |
|---|---|---|---|
| POST | `/device/register` | — | 注册设备，返回 `deviceId / token / bindCode` |
| POST | `/device/rebind-code` | `X-Device-Token` | 重置绑定码（旧码立即作废） |
| POST | `/report` | `X-Device-Token` | 批量上报位置，响应携带最新配置 |
| POST | `/auth/register` `/auth/login` | — | 返回 30 天 JWT |
| GET | `/devices` | Bearer | 我的老人列表（含最新位置摘要、配置同步状态、未读告警数） |
| POST | `/devices/bind` | Bearer | 扫码绑定：`{bindCode, nickname, avatar?}` |
| DELETE | `/devices/:id/bind` | Bearer | 解绑当前账号 |
| PUT | `/devices/:id/profile` | Bearer | 改称呼（用户级）/ 头像（设备级） |
| GET | `/devices/:id/summary` | Bearer | 最新位置 / 电量 / 模式 / 围栏 |
| GET | `/devices/:id/locations` | Bearer | 历史轨迹（服务端抽稀） |
| PUT | `/devices/:id/settings` | Bearer | 模式 / 上报频率 / 围栏开关 |
| GET/PUT | `/devices/:id/geofence` | Bearer | 电子围栏（circle / polygon） |
| GET | `/alerts` | Bearer | 告警列表 |
| PUT | `/alerts/read` | Bearer | 标记已读（单条 / 全部） |

## 数据表

`users` `devices` `device_settings` `device_state` `locations` `geofences` `user_devices` `alerts`

> `device_state` 是在 DESIGN 6.3 之外新增的表，用于承载「围栏状态机 + 告警去重标记」：
> `in_fence / fence_initialized / battery_low_alerted / offline_alerted / guard_off_alerted`。

## 联调

```bash
npm run dev -- --test-scheduled     # --test-scheduled 才能手动触发 Cron
bash scripts/smoke.sh               # 另开终端
curl "http://127.0.0.1:8791/__scheduled?cron=0+*+*+*+*"   # 手动跑一次失联检测
```

`node_modules` 里已含 `wrangler`，本地开发不需要 Cloudflare 账号；
`wrangler d1 execute findma --local` 可以直接查本地 SQLite。

## 部署到 Cloudflare

已接入 **Workers Builds**：推送到 GitHub `main` 会自动触发构建与部署。
CI 侧固定的 Worker 名是 **`findma`**，所以 `wrangler.toml` 的 `name` 必须与它一致，
否则会出现 `Failed to match Worker name` 警告，CI 会覆盖该字段并尝试自动提 PR 修正配置。

首次部署（或换 Cloudflare 账号）必须按顺序做三件事，**缺任何一步部署都会失败**：

```bash
cd worker
npm install

# ① D1 数据库：创建后把 uuid 回填到 wrangler.toml 的 database_id
npx wrangler d1 create findma
npx wrangler d1 list          # 库已存在时用这个查 uuid

# ② 把建表脚本应用到【远程】库（不加 --remote 只会动本地）
npm run db:init:remote

# ③ 写入运行时密钥（缺它所有需要登录的接口都会返回 SERVER_MISCONFIGURED）
npm run secret:jwt
```

### 当前线上状态

| 项 | 值 |
|---|---|
| Worker 名 | `findma` |
| D1 数据库 | `findma` · `5fb6feaf-456f-482e-999c-a9c13bc7b4db` |
| 远程表 | 8 张（已执行 `db:init:remote`） |
| `JWT_SECRET` | 已通过 `wrangler secret put` 写入 |
| wrangler | v4（`^4.130.0`，v3 已进入维护状态，CI 会提示升级） |

### 常见报错

| 报错 / 现象 | 原因 | 处理 |
|---|---|---|
| `binding DB of type d1 must have a valid database_id [code: 10021]` | `wrangler.toml` 的 `database_id` 还是占位符 | 按上面 ① 回填真实 uuid 后重新推送 |
| `Failed to match Worker name` | `wrangler.toml` 的 `name` 与 CI 不一致 | 保持 `name = "findma"` |
| 部署成功但登录返回 `SERVER_MISCONFIGURED` | 没写 `JWT_SECRET` | 按上面 ③ 执行 `npm run secret:jwt` |
| `You are about to publish a Workers Service that was last published via the Cloudflare Dashboard` | Worker 最早是在 Dashboard 建的 | 正常提示，确认即可；之后以仓库配置为准 |
| 改了 `database_id` 后本地表"消失" | 本地 D1 文件按 `database_id` 哈希命名存放 | 重跑 `npm run db:init:local` |

### 推送前的本地自检

CI 失败一次要等好几分钟，推送前可以先在本地把同样的检查跑一遍：

```bash
npx tsc --noEmit                      # 类型检查
npx wrangler deploy --dry-run         # 只打包不上传，能验证配置与绑定
```

### 为什么必须绑自定义域名

`*.workers.dev` 在国内无法直连。实测 `findma.iceet.workers.dev` 用不同 DNS 解析会得到
一堆互不相干的 IP（Meta / Twitter 网段），属于典型的 **DNS 污染**，TCP 连接直接超时：

| DNS | 解析结果 |
|---|---|
| 系统默认 | `104.244.43.167` |
| 阿里 223.5.5.5 | `69.171.242.11`（Meta 段） |
| Google 8.8.8.8 | `157.240.10.41` |
| 114.114.114.114 | `103.240.180.117` |

而同一时间 `api.cloudflare.com` 是通的（所以 `wrangler deploy` 在本地能正常跑完）。
**部署成功 ≠ 手机能访问**，必须绑定自定义域名：

1. 把域名 NS 托管到 Cloudflare（或已在同一账号下）
2. 取消 `wrangler.toml` 末尾 `[[routes]]` 的注释并改成你的域名，
   或到 Dashboard → Workers → `findma` → Settings → Domains & Routes 添加 Custom Domain
3. 重新推送，CI 会自动部署并生效

> **小技巧**：绑定后可先在本机验证 `curl https://<你的域名>/health`，
> 再改两端 App 的 `API_BASE`。

## 参数调优（wrangler.toml 的 [vars]）

| 变量 | 默认 | 含义 |
|---|---|---|
| `DEFAULT_NORMAL_INTERVAL_SEC` | 1200 | 普通模式默认上报间隔 |
| `DEFAULT_LOST_INTERVAL_SEC` | 60 | 丢失模式默认上报间隔 |
| `FENCE_BUFFER_M` | 50 | 围栏缓冲带（防边界抖动） |
| `FENCE_ACCURACY_GATE_M` | 150 | 精度门槛，超过该值的点不参与围栏判定 |
| `LOW_BATTERY_THRESHOLD` | 20 | 低电告警阈值（%） |
| `OFFLINE_MIN_SEC` | 7200 | 失联判定下限：`max(3×当前间隔, 该值)` |
| `LOCATION_RETENTION_DAYS` | 180 | 轨迹保留天数 |
| `MAX_AVATAR_BYTES` | 102400 | 头像 base64 解码后最大字节数 |
