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
