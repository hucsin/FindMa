import { Hono } from 'hono';
import type { AppEnv, Env } from '../types';
import { readJson } from '../http';
import { readConfig } from '../config';
import { deviceAuth } from '../middleware/deviceAuth';
import { sha256Hex } from '../utils/auth';
import { newBindCode, newDeviceToken, newId } from '../utils/id';
import { getOrCreateSettings, getOrCreateState } from '../services/store';

const r = new Hono<AppEnv>();

/**
 * POST /api/v1/device/register
 * 老人端首次启动调用（无鉴权）。返回 deviceId + token + bindCode（二维码内容）。
 */
r.post('/register', async (c) => {
  const cfg = readConfig(c.env);
  const body = (await readJson<{ name?: string }>(c)) ?? {};

  const deviceId = newId();
  const token = newDeviceToken();
  const bindCode = await uniqueBindCode(c.env);
  const now = Date.now();
  const name =
    typeof body.name === 'string' && body.name.trim() ? body.name.trim().slice(0, 32) : '老人手机';

  await c.env.DB.prepare(
    `INSERT INTO devices (id, name, avatar, token_hash, invite_code, created_at, last_seen_at)
     VALUES (?, ?, NULL, ?, ?, ?, NULL)`,
  )
    .bind(deviceId, name, await sha256Hex(token), bindCode, now)
    .run();

  // 预建配置与状态行，后续读路径不再需要判断存在性
  await getOrCreateSettings(c.env, deviceId, cfg);
  await getOrCreateState(c.env, deviceId);

  return c.json({ deviceId, token, bindCode, serverTs: now }, 201);
});

/**
 * POST /api/v1/device/rebind-code
 * 重置绑定码：旧码（旧二维码）立即作废，防泄露（DESIGN 5.4）。
 */
r.post('/rebind-code', deviceAuth, async (c) => {
  const deviceId = c.get('deviceId');
  const bindCode = await uniqueBindCode(c.env);
  await c.env.DB.prepare('UPDATE devices SET invite_code = ? WHERE id = ?')
    .bind(bindCode, deviceId)
    .run();
  return c.json({ bindCode, serverTs: Date.now() });
});

/** 生成不与现有设备冲突的绑定码 */
async function uniqueBindCode(env: Env): Promise<string> {
  for (let i = 0; i < 8; i++) {
    const code = newBindCode();
    const hit = await env.DB.prepare('SELECT 1 AS x FROM devices WHERE invite_code = ?')
      .bind(code)
      .first();
    if (!hit) return code;
  }
  // 32^8 空间下几乎不可能走到这里；兜底用更长随机串
  return `${newBindCode()}${newBindCode()}`;
}

export default r;
