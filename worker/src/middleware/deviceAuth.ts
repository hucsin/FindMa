import type { Context, Next } from 'hono';
import type { AppEnv } from '../types';
import { err } from '../http';
import { sha256Hex } from '../utils/auth';

/**
 * 老人端鉴权：请求头 X-Device-Token 明文比对哈希（D1 只存 SHA-256，DESIGN 10）。
 */
export async function deviceAuth(c: Context<AppEnv>, next: Next) {
  const token = (c.req.header('X-Device-Token') || '').trim();
  if (!token) return err(c, 401, 'NO_DEVICE_TOKEN', '缺少 X-Device-Token 请求头');

  const hash = await sha256Hex(token);
  const row = await c.env.DB.prepare('SELECT id FROM devices WHERE token_hash = ?')
    .bind(hash)
    .first<{ id: string }>();

  if (!row) return err(c, 401, 'BAD_DEVICE_TOKEN', '设备令牌无效');

  c.set('deviceId', row.id);
  await next();
}
