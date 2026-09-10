import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv, GeofenceRow } from '../types';
import { LIMITS, effectiveIntervalSec, readConfig } from '../config';
import { clampInt, err, isNonEmptyString, readJson } from '../http';
import { userAuth } from '../middleware/userAuth';
import { normalizeBindCode, newId } from '../utils/id';
import { isValidLatLng, parsePolygon } from '../utils/geo';
import { getOrCreateSettings, getOwnedDevice, getActiveFence, intervalOf, syncStateOf } from '../services/store';

const r = new Hono<AppEnv>();

// 本路由下所有接口都需要子女端登录态
r.use('*', userAuth);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/devices —— 我的老人列表（含最新位置摘要、配置状态、未读告警数）
// ─────────────────────────────────────────────────────────────────────────────
r.get('/', async (c) => {
  const userId = c.get('userId');

  const rows = await c.env.DB.prepare(
    `SELECT d.id, d.name, d.avatar, d.last_seen_at,
            ud.nickname, ud.created_at AS bound_at,
            s.mode, s.normal_interval_sec, s.lost_interval_sec, s.fence_enabled,
            s.settings_ver, s.synced_ver,
            l.lat, l.lng, l.accuracy, l.battery, l.charging, l.provider, l.in_fence,
            l.reported_at AS loc_ts,
            (SELECT COUNT(*) FROM alerts a WHERE a.device_id = d.id AND a.read = 0) AS unread
       FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
       LEFT JOIN device_settings s ON s.device_id = d.id
       LEFT JOIN locations l
              ON l.id = (SELECT id FROM locations WHERE device_id = d.id ORDER BY reported_at DESC, id DESC LIMIT 1)
      WHERE ud.user_id = ?
      ORDER BY ud.created_at DESC`,
  )
    .bind(userId)
    .all<Record<string, unknown>>();

  const now = Date.now();
  const devices = (rows.results ?? []).map((row) => {
    const mode = String(row.mode ?? 'NORMAL');
    const normalIntervalSec = Number(row.normal_interval_sec ?? 1200);
    const lostIntervalSec = Number(row.lost_interval_sec ?? 60);
    const intervalSec = effectiveIntervalSec(mode, normalIntervalSec, lostIntervalSec);
    const lastSeenAt = row.last_seen_at == null ? null : Number(row.last_seen_at);

    return {
      id: row.id,
      name: row.name,
      nickname: row.nickname,
      avatar: row.avatar,
      lastSeenAt,
      online: isOnline(lastSeenAt, intervalSec, now),
      unreadAlerts: Number(row.unread ?? 0),
      settings: {
        mode,
        normalIntervalSec,
        lostIntervalSec,
        fenceEnabled: Number(row.fence_enabled ?? 1) === 1,
        reportIntervalSec: intervalSec,
        settingsVer: Number(row.settings_ver ?? 1),
        syncedVer: Number(row.synced_ver ?? 1),
        syncState: syncStateOf({
          settings_ver: Number(row.settings_ver ?? 1),
          synced_ver: Number(row.synced_ver ?? 1),
        }),
      },
      lastLocation:
        row.loc_ts == null
          ? null
          : {
              lat: Number(row.lat),
              lng: Number(row.lng),
              accuracy: numOrNull(row.accuracy),
              battery: numOrNull(row.battery),
              charging: row.charging == null ? null : Number(row.charging) === 1,
              provider: row.provider,
              inFence: row.in_fence == null ? null : Number(row.in_fence) === 1,
              reportedAt: Number(row.loc_ts),
            },
    };
  });

  return c.json({ devices });
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/devices/bind —— 扫码绑定（bindCode + 称呼 + 可选头像）
// ─────────────────────────────────────────────────────────────────────────────
r.post('/bind', async (c) => {
  const userId = c.get('userId');
  const cfg = readConfig(c.env);
  const body = await readJson<{ bindCode?: string; nickname?: string; avatar?: string }>(c);

  const bindCode = normalizeBindCode(body?.bindCode ?? '');
  if (!bindCode) return err(c, 400, 'NO_BIND_CODE', '请提供绑定码');
  if (!isNonEmptyString(body?.nickname)) return err(c, 400, 'NO_NICKNAME', '请填写对老人的称呼');

  const nickname = body!.nickname!.trim().slice(0, 16);

  const device = await c.env.DB.prepare(
    'SELECT id, name, avatar FROM devices WHERE invite_code = ?',
  )
    .bind(bindCode)
    .first<{ id: string; name: string; avatar: string | null }>();
  if (!device) return err(c, 404, 'BAD_BIND_CODE', '绑定码无效或已被重置');

  const already = await c.env.DB.prepare(
    'SELECT 1 AS x FROM user_devices WHERE user_id = ? AND device_id = ?',
  )
    .bind(userId, device.id)
    .first();
  if (already) return err(c, 409, 'ALREADY_BOUND', '你已经绑定过这位老人了');

  let avatar = device.avatar;
  if (body?.avatar != null && body.avatar !== '') {
    const decoded = decodeAvatar(body.avatar, cfg.maxAvatarBytes);
    if ('message' in decoded) return err(c, 400, 'BAD_AVATAR', decoded.message);
    avatar = decoded.value;
  }

  const now = Date.now();
  const stmts: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `INSERT INTO user_devices (user_id, device_id, nickname, role, created_at)
       VALUES (?, ?, ?, 'owner', ?)`,
    ).bind(userId, device.id, nickname, now),
  ];
  if (avatar !== device.avatar) {
    stmts.push(c.env.DB.prepare('UPDATE devices SET avatar = ? WHERE id = ?').bind(avatar, device.id));
  }
  // 兜底：万一是历史数据缺配置行
  await getOrCreateSettings(c.env, device.id, cfg);
  await c.env.DB.batch(stmts);

  return c.json(
    { device: { id: device.id, name: device.name, avatar, nickname } },
    201,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/devices/:id/profile —— 改称呼（用户级）或头像（设备级共享）
// ─────────────────────────────────────────────────────────────────────────────
r.put('/:id/profile', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');

  const cfg = readConfig(c.env);
  const body = await readJson<{ nickname?: string; avatar?: string }>(c);
  if (!body) return err(c, 400, 'BAD_JSON', '请求体必须是合法 JSON');

  const stmts: D1PreparedStatement[] = [];

  if (body.nickname != null) {
    if (!isNonEmptyString(body.nickname)) return err(c, 400, 'BAD_NICKNAME', '称呼不能为空');
    stmts.push(
      c.env.DB.prepare('UPDATE user_devices SET nickname = ? WHERE user_id = ? AND device_id = ?')
        .bind(body.nickname.trim().slice(0, 16), c.get('userId'), deviceId),
    );
  }

  if (body.avatar != null) {
    const decoded = decodeAvatar(body.avatar, cfg.maxAvatarBytes);
    if ('message' in decoded) return err(c, 400, 'BAD_AVATAR', decoded.message);
    stmts.push(c.env.DB.prepare('UPDATE devices SET avatar = ? WHERE id = ?').bind(decoded.value, deviceId));
  }

  if (!stmts.length) return err(c, 400, 'NOTHING_TO_UPDATE', '没有需要更新的字段');
  await c.env.DB.batch(stmts);

  const fresh = await getOwnedDevice(c.env, c.get('userId'), deviceId);
  return c.json({
    device: { id: deviceId, name: fresh?.name, avatar: fresh?.avatar, nickname: fresh?.nickname },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/v1/devices/:id/bind —— 解绑（只解除当前账号；老人端与其他子女不受影响）
// ─────────────────────────────────────────────────────────────────────────────
r.delete('/:id/bind', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');

  await c.env.DB.prepare('DELETE FROM user_devices WHERE user_id = ? AND device_id = ?')
    .bind(c.get('userId'), deviceId)
    .run();

  return c.json({ ok: true, serverTs: Date.now() });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/devices/:id/summary —— 最新位置 / 电量 / 模式 / 围栏 / 最后上报
// ─────────────────────────────────────────────────────────────────────────────
r.get('/:id/summary', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');

  const cfg = readConfig(c.env);
  const settings = await getOrCreateSettings(c.env, deviceId, cfg);
  const fence = await getActiveFence(c.env, deviceId);
  const last = await c.env.DB.prepare(
    `SELECT lat, lng, accuracy, speed, battery, charging, provider, net_type, vpn_active,
            in_fence, dev_ts, reported_at
       FROM locations WHERE device_id = ? ORDER BY reported_at DESC, id DESC LIMIT 1`,
  )
    .bind(deviceId)
    .first<Record<string, unknown>>();

  const intervalSec = intervalOf(settings);
  const lastSeenAt = owned.last_seen_at;

  return c.json({
    device: {
      id: deviceId,
      name: owned.name,
      avatar: owned.avatar,
      nickname: owned.nickname,
    },
    lastSeenAt,
    online: isOnline(lastSeenAt, intervalSec, Date.now()),
    settings: {
      mode: settings.mode,
      normalIntervalSec: settings.normal_interval_sec,
      lostIntervalSec: settings.lost_interval_sec,
      fenceEnabled: settings.fence_enabled === 1,
      reportIntervalSec: intervalSec,
      settingsVer: settings.settings_ver,
      syncedVer: settings.synced_ver,
      syncState: syncStateOf(settings),
    },
    lastLocation: last
      ? {
          lat: Number(last.lat),
          lng: Number(last.lng),
          accuracy: numOrNull(last.accuracy),
          speed: numOrNull(last.speed),
          battery: numOrNull(last.battery),
          charging: last.charging == null ? null : Number(last.charging) === 1,
          provider: last.provider,
          netType: last.net_type,
          vpnActive: last.vpn_active == null ? null : Number(last.vpn_active) === 1,
          inFence: last.in_fence == null ? null : Number(last.in_fence) === 1,
          devTs: numOrNull(last.dev_ts),
          reportedAt: Number(last.reported_at),
        }
      : null,
    fence: fence ? serializeFence(fence) : null,
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/devices/:id/locations?from&to&limit —— 历史轨迹（服务端抽稀）
// ─────────────────────────────────────────────────────────────────────────────
r.get('/:id/locations', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');

  const now = Date.now();
  const to = clampInt(c.req.query('to'), 0, Number.MAX_SAFE_INTEGER, now) || now;
  const from = clampInt(c.req.query('from'), 0, Number.MAX_SAFE_INTEGER, to - 86400_000) || to - 86400_000;
  const limit = clampInt(c.req.query('limit'), 10, LIMITS.maxTrackPoints, 1000);

  const rows = await c.env.DB.prepare(
    `SELECT lat, lng, accuracy, speed, bearing, battery, in_fence, provider, dev_ts, reported_at
       FROM locations
      WHERE device_id = ? AND reported_at >= ? AND reported_at <= ?
      ORDER BY reported_at ASC, id ASC
      LIMIT ?`,
  )
    .bind(deviceId, Math.min(from, to), Math.max(from, to), LIMITS.maxTrackPoints)
    .all<Record<string, unknown>>();

  const all = (rows.results ?? []).map((x) => ({
    lat: Number(x.lat),
    lng: Number(x.lng),
    accuracy: numOrNull(x.accuracy),
    speed: numOrNull(x.speed),
    bearing: numOrNull(x.bearing),
    battery: numOrNull(x.battery),
    inFence: x.in_fence == null ? null : Number(x.in_fence) === 1,
    provider: x.provider,
    devTs: numOrNull(x.dev_ts),
    reportedAt: Number(x.reported_at),
  }));

  const points = decimate(all, limit);
  return c.json({ from, to, total: all.length, returned: points.length, points });
});

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/v1/devices/:id/settings —— 模式 / 上报频率 / 围栏开关
// ─────────────────────────────────────────────────────────────────────────────
r.put('/:id/settings', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');

  const cfg = readConfig(c.env);
  const body = await readJson<{
    mode?: string;
    normalIntervalSec?: number;
    lostIntervalSec?: number;
    fenceEnabled?: boolean;
  }>(c);
  if (!body) return err(c, 400, 'BAD_JSON', '请求体必须是合法 JSON');

  const current = await getOrCreateSettings(c.env, deviceId, cfg);

  const mode = body.mode == null ? current.mode : String(body.mode).toUpperCase();
  if (!['NORMAL', 'WATCH', 'LOST'].includes(mode)) {
    return err(c, 400, 'BAD_MODE', 'mode 只能是 NORMAL / WATCH / LOST');
  }

  const normalIntervalSec =
    body.normalIntervalSec == null
      ? current.normal_interval_sec
      : clampInt(body.normalIntervalSec, LIMITS.minIntervalSec, LIMITS.maxIntervalSec, current.normal_interval_sec);
  const lostIntervalSec =
    body.lostIntervalSec == null
      ? current.lost_interval_sec
      : clampInt(body.lostIntervalSec, LIMITS.minIntervalSec, LIMITS.maxIntervalSec, current.lost_interval_sec);
  const fenceEnabled =
    body.fenceEnabled == null ? current.fence_enabled === 1 : body.fenceEnabled === true;

  const now = Date.now();
  await c.env.DB.prepare(
    `UPDATE device_settings
        SET mode = ?, normal_interval_sec = ?, lost_interval_sec = ?, fence_enabled = ?,
            settings_ver = settings_ver + 1, updated_at = ?
      WHERE device_id = ?`,
  )
    .bind(mode, normalIntervalSec, lostIntervalSec, fenceEnabled ? 1 : 0, now, deviceId)
    .run();

  const fresh = await getOrCreateSettings(c.env, deviceId, cfg);
  return c.json({
    settings: {
      mode: fresh.mode,
      normalIntervalSec: fresh.normal_interval_sec,
      lostIntervalSec: fresh.lost_interval_sec,
      fenceEnabled: fresh.fence_enabled === 1,
      reportIntervalSec: intervalOf(fresh),
      settingsVer: fresh.settings_ver,
      syncedVer: fresh.synced_ver,
      syncState: syncStateOf(fresh),
    },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET / PUT /api/v1/devices/:id/geofence —— 电子围栏
// ─────────────────────────────────────────────────────────────────────────────
r.get('/:id/geofence', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');
  const fence = await getActiveFence(c.env, deviceId);
  return c.json({ fence: fence ? serializeFence(fence) : null });
});

r.put('/:id/geofence', async (c) => {
  const { deviceId, owned } = await requireOwned(c);
  if (!owned) return err(c, 404, 'NOT_FOUND', '设备不存在或未绑定');

  const body = await readJson<{
    name?: string;
    type?: string;
    centerLat?: number;
    centerLng?: number;
    radiusM?: number;
    polygon?: number[][];
    enabled?: boolean;
  }>(c);
  if (!body) return err(c, 400, 'BAD_JSON', '请求体必须是合法 JSON');

  const type = body.type === 'polygon' ? 'polygon' : body.type === 'circle' ? 'circle' : null;
  if (!type) return err(c, 400, 'BAD_TYPE', 'type 只能是 circle 或 polygon');

  const now = Date.now();
  const name = isNonEmptyString(body.name) ? body.name.trim().slice(0, 24) : '家';
  const enabled = body.enabled === false ? 0 : 1;

  let centerLat: number | null = null;
  let centerLng: number | null = null;
  let radiusM: number | null = null;
  let polygonJson: string | null = null;

  if (type === 'circle') {
    if (!isValidLatLng(body.centerLat, body.centerLng)) {
      return err(c, 400, 'BAD_CENTER', '圆心经纬度不合法');
    }
    centerLat = Number(body.centerLat);
    centerLng = Number(body.centerLng);
    radiusM = clampInt(body.radiusM, 20, 20000, 300);
  } else {
    const poly = Array.isArray(body.polygon) ? body.polygon : [];
    const clean = poly.filter(
      (p) => Array.isArray(p) && p.length >= 2 && isValidLatLng(p[0], p[1]),
    ) as number[][];
    if (clean.length < 3) return err(c, 400, 'BAD_POLYGON', '多边形至少需要 3 个合法顶点');
    polygonJson = JSON.stringify(clean);
  }

  // MVP 每设备一个围栏：先删后插，保证只有一条生效记录
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM geofences WHERE device_id = ?').bind(deviceId),
    c.env.DB.prepare(
      `INSERT INTO geofences
         (id, device_id, name, type, center_lat, center_lng, radius_m, polygon_json, enabled, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(newId(), deviceId, name, type, centerLat, centerLng, radiusM, polygonJson, enabled, now),
    // 围栏变更后重新建立状态：下一次上报按新围栏建立初始判定（DESIGN 6.4-5）
    c.env.DB.prepare(
      `INSERT INTO device_state (device_id, in_fence, fence_initialized, battery_low_alerted, offline_alerted, guard_off_alerted, updated_at)
       VALUES (?, NULL, 0, 0, 0, 0, ?)
       ON CONFLICT(device_id) DO UPDATE SET in_fence = NULL, fence_initialized = 0, updated_at = excluded.updated_at`,
    ).bind(deviceId, now),
  ]);

  const fence = await getActiveFence(c.env, deviceId);
  return c.json({ fence: fence ? serializeFence(fence) : null });
});

// ───────────────────────────────────────── 工具 ─────────────────────────────

/** 取 :id 并校验归属；owned 为 null 表示不存在或不属于当前用户 */
async function requireOwned(c: Context<AppEnv>) {
  const deviceId = c.req.param('id') ?? '';
  const owned = deviceId ? await getOwnedDevice(c.env, c.get('userId'), deviceId) : null;
  return { deviceId, owned };
}

function serializeFence(f: GeofenceRow) {
  return {
    id: f.id,
    name: f.name,
    type: f.type,
    centerLat: f.center_lat,
    centerLng: f.center_lng,
    radiusM: f.radius_m,
    polygon: parsePolygon(f.polygon_json),
    enabled: f.enabled === 1,
    updatedAt: f.updated_at,
  };
}

/** 在线判定：最后上报时间在 max(3 × 当前间隔, 5 分钟) 内视为在线 */
function isOnline(lastSeenAt: number | null, intervalSec: number, now: number): boolean {
  if (lastSeenAt == null) return false;
  const windowMs = Math.max(3 * intervalSec, 300) * 1000;
  return now - lastSeenAt <= windowMs;
}

/** 轨迹抽稀：均匀采样到 limit 个点，首尾必留（DESIGN 8.1） */
function decimate<T>(points: T[], limit: number): T[] {
  if (points.length <= limit || limit < 3) return points;
  const out: T[] = [points[0]];
  const step = (points.length - 1) / (limit - 1);
  for (let i = 1; i < limit - 1; i++) {
    out.push(points[Math.round(i * step)]);
  }
  out.push(points[points.length - 1]);
  return out;
}

function numOrNull(v: unknown): number | null {
  if (v == null) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** 校验头像 base64（可带 data URL 前缀），返回清洗后的 base64 或错误信息 */
function decodeAvatar(raw: string, maxBytes: number): { value: string } | { message: string } {
  let s = String(raw).trim();
  const m = /^data:image\/[a-z+]+;base64,(.*)$/i.exec(s);
  if (m) s = m[1];
  s = s.replace(/\s+/g, '');
  if (!s || !/^[A-Za-z0-9+/=]+$/.test(s)) return { message: '头像必须是 base64 编码的图片' };
  const bytes = Math.floor((s.length * 3) / 4);
  if (bytes > maxBytes) {
    return { message: `头像过大（约 ${Math.round(bytes / 1024)}KB），请压缩到 ${Math.round(maxBytes / 1024)}KB 以内` };
  }
  return { value: s };
}

export default r;
