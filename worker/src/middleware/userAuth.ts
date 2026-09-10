import type { Context, Next } from 'hono';
import type { AppEnv } from '../types';
import { err } from '../http';
import { parseBearer, verifyJwt } from '../utils/auth';

/** 子女端鉴权：Authorization: Bearer <JWT>（HS256，30 天有效） */
export async function userAuth(c: Context<AppEnv>, next: Next) {
  const token = parseBearer(c.req.header('Authorization'));
  if (!token) return err(c, 401, 'NO_TOKEN', '缺少 Authorization: Bearer <token>');

  const payload = await verifyJwt(token, c.env.JWT_SECRET);
  if (!payload) return err(c, 401, 'BAD_TOKEN', '登录态无效或已过期');

  c.set('userId', payload.sub);
  await next();
}
