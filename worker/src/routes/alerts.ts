import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { LIMITS } from '../config';
import { clampInt, err, readJson } from '../http';
import { userAuth } from '../middleware/userAuth';

const r = new Hono<AppEnv>();

r.use('*', userAuth);

/**
 * GET /api/v1/alerts?deviceId=&onlyUnread=&limit=
 * 只返回当前用户名下设备的告警（DESIGN 6.2）。
 */
r.get('/', async (c) => {
  const userId = c.get('userId');
  const deviceId = c.req.query('deviceId') ?? '';
  const onlyUnread = c.req.query('onlyUnread') === 'true' || c.req.query('onlyUnread') === '1';
  const limit = clampInt(c.req.query('limit'), 1, LIMITS.maxAlerts, 50);

  const where: string[] = ['a.device_id IN (SELECT device_id FROM user_devices WHERE user_id = ?)'];
  const args: unknown[] = [userId];
  if (deviceId) {
    where.push('a.device_id = ?');
    args.push(deviceId);
  }
  if (onlyUnread) where.push('a.read = 0');
  args.push(limit);

  const rows = await c.env.DB.prepare(
    `SELECT a.id, a.device_id, a.type, a.title, a.body, a.payload_json, a.read, a.created_at,
            ud.nickname, d.avatar
       FROM alerts a
       LEFT JOIN user_devices ud ON ud.device_id = a.device_id AND ud.user_id = ?
       LEFT JOIN devices d ON d.id = a.device_id
      WHERE ${where.join(' AND ')}
      ORDER BY a.created_at DESC
      LIMIT ?`,
  )
    .bind(userId, ...args)
    .all<Record<string, unknown>>();

  const alerts = (rows.results ?? []).map((x) => ({
    id: Number(x.id),
    deviceId: x.device_id,
    nickname: x.nickname,
    avatar: x.avatar,
    type: x.type,
    title: x.title,
    body: x.body,
    payload: x.payload_json ? safeParse(String(x.payload_json)) : null,
    read: Number(x.read) === 1,
    createdAt: Number(x.created_at),
  }));

  const unread = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM alerts
      WHERE read = 0 AND device_id IN (SELECT device_id FROM user_devices WHERE user_id = ?)`,
  )
    .bind(userId)
    .first<{ n: number }>();

  return c.json({ alerts, unreadTotal: Number(unread?.n ?? 0) });
});

/**
 * PUT /api/v1/alerts/read
 * body: { ids?: number[], all?: boolean, deviceId?: string }
 */
r.put('/read', async (c) => {
  const userId = c.get('userId');
  const body = await readJson<{ ids?: number[]; all?: boolean; deviceId?: string }>(c);
  if (!body) return err(c, 400, 'BAD_JSON', '请求体必须是合法 JSON');

  const scope = 'device_id IN (SELECT device_id FROM user_devices WHERE user_id = ?)';
  const now = Date.now();

  if (body.all === true) {
    if (body.deviceId) {
      const res = await c.env.DB.prepare(
        `UPDATE alerts SET read = 1 WHERE read = 0 AND ${scope} AND device_id = ?`,
      )
        .bind(userId, body.deviceId)
        .run();
      return c.json({ updated: changes(res), serverTs: now });
    }
    const res = await c.env.DB.prepare(`UPDATE alerts SET read = 1 WHERE read = 0 AND ${scope}`)
      .bind(userId)
      .run();
    return c.json({ updated: changes(res), serverTs: now });
  }

  const ids = (body.ids ?? []).map((n) => Number(n)).filter((n) => Number.isInteger(n));
  if (!ids.length) return err(c, 400, 'NO_IDS', '请提供 ids 数组或 all=true');

  const placeholders = ids.map(() => '?').join(',');
  const res = await c.env.DB.prepare(
    `UPDATE alerts SET read = 1 WHERE read = 0 AND ${scope} AND id IN (${placeholders})`,
  )
    .bind(userId, ...ids)
    .run();
  return c.json({ updated: changes(res), serverTs: now });
});

function changes(res: { meta?: unknown }): number {
  return Number((res.meta as { changes?: number } | undefined)?.changes ?? 0);
}

function safeParse(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

export default r;
