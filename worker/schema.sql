-- ============================================================================
-- FindMa · D1 (SQLite) 建表脚本
-- 对应 DESIGN.md 第 6.3 节；另新增 device_state 表用于"状态翻转判定/告警去重"
-- 执行：npm run db:init:local   /   npm run db:init:remote
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ── 子女用户 ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  username      TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,              -- PBKDF2-SHA256
  created_at    INTEGER NOT NULL
);

-- ── 老人设备 ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS devices (
  id          TEXT PRIMARY KEY,
  name        TEXT DEFAULT '老人手机',
  avatar      TEXT,                          -- base64 JPEG（设备级共享，≤100KB）
  token_hash  TEXT NOT NULL,                 -- SHA-256(device token)，原文只在老人手机
  invite_code TEXT UNIQUE NOT NULL,          -- 绑定码（二维码内容，可重置）
  created_at  INTEGER NOT NULL,
  last_seen_at INTEGER
);

-- ── 设备配置（模式在这里切换）──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS device_settings (
  device_id           TEXT PRIMARY KEY,
  mode                TEXT NOT NULL DEFAULT 'NORMAL',  -- NORMAL | WATCH | LOST
  normal_interval_sec INTEGER NOT NULL DEFAULT 1200,
  lost_interval_sec   INTEGER NOT NULL DEFAULT 60,
  fence_enabled       INTEGER NOT NULL DEFAULT 1,
  settings_ver        INTEGER NOT NULL DEFAULT 1,      -- 每次修改 +1
  synced_ver          INTEGER NOT NULL DEFAULT 1,      -- 设备已确认的版本
  updated_at          INTEGER NOT NULL
);

-- ── 设备运行状态（围栏状态机 + 告警去重；DESIGN 未列，实现所需）────────────
CREATE TABLE IF NOT EXISTS device_state (
  device_id            TEXT PRIMARY KEY,
  in_fence             INTEGER,                          -- 1 在内 / 0 在外 / NULL 未判定
  fence_initialized    INTEGER NOT NULL DEFAULT 0,       -- 是否已建立初始围栏状态
  battery_low_alerted  INTEGER NOT NULL DEFAULT 0,       -- 本充电周期是否已发低电告警
  offline_alerted      INTEGER NOT NULL DEFAULT 0,       -- 是否已发失联告警（用于 RECOVERED）
  guard_off_alerted    INTEGER NOT NULL DEFAULT 0,       -- 是否已发守护失效告警
  updated_at           INTEGER NOT NULL
);

-- ── 位置记录（时间序列）────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS locations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id   TEXT NOT NULL,
  lat         REAL NOT NULL,
  lng         REAL NOT NULL,
  accuracy    REAL,
  speed       REAL,
  bearing     REAL,
  battery     REAL,
  charging    INTEGER,
  provider    TEXT,
  net_type    TEXT,
  vpn_active  INTEGER,
  in_fence    INTEGER,                     -- 1 在内 / 0 在外 / NULL 未判定
  dev_ts      INTEGER,
  reported_at INTEGER NOT NULL             -- 以服务器接收时间排序（防设备时钟漂移）
);
CREATE INDEX IF NOT EXISTS idx_loc_dev_time ON locations(device_id, reported_at);

-- ── 电子围栏（MVP 每设备一个，表结构天然支持多个）──────────────────────────
CREATE TABLE IF NOT EXISTS geofences (
  id           TEXT PRIMARY KEY,
  device_id    TEXT NOT NULL,
  name         TEXT DEFAULT '家',
  type         TEXT NOT NULL,              -- circle | polygon
  center_lat   REAL,
  center_lng   REAL,
  radius_m     REAL,
  polygon_json TEXT,                       -- [[lat,lng],...]
  enabled      INTEGER NOT NULL DEFAULT 1,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fence_device ON geofences(device_id, updated_at);

-- ── 用户-设备绑定（支持多个子女，各自独立称呼）────────────────────────────
CREATE TABLE IF NOT EXISTS user_devices (
  user_id    TEXT NOT NULL,
  device_id  TEXT NOT NULL,
  nickname   TEXT NOT NULL,                -- 称呼（用户级，如"爸爸"/"爷爷"）
  role       TEXT DEFAULT 'owner',
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_ud_device ON user_devices(device_id);

-- ── 告警 ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alerts (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id    TEXT NOT NULL,
  type         TEXT NOT NULL,  -- OUT_OF_FENCE|BACK_IN_FENCE|LOW_BATTERY|OFFLINE|RECOVERED|GUARD_OFF
  title        TEXT,
  body         TEXT,
  payload_json TEXT,
  read         INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_alerts_dev_time ON alerts(device_id, created_at);
CREATE INDEX IF NOT EXISTS idx_alerts_unread ON alerts(device_id, read);
