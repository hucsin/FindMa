import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { err, isNonEmptyString, readJson } from '../http';
import { hashPassword, signJwt, verifyPassword } from '../utils/auth';
import { newId } from '../utils/id';

const r = new Hono<AppEnv>();

interface UserRow {
  id: string;
  username: string;
  password_hash: string;
}

/** POST /api/v1/auth/register —— 用户名密码注册，返回 30 天 JWT */
r.post('/register', async (c) => {
  const body = await readJson<{ username?: string; password?: string }>(c);
  const username = (body?.username ?? '').trim();
  const password = body?.password ?? '';

  const check = validateCredentials(username, password);
  if (check) return err(c, 400, 'BAD_CREDENTIALS', check);

  const dup = await c.env.DB.prepare('SELECT 1 AS x FROM users WHERE username = ?')
    .bind(username)
    .first();
  if (dup) return err(c, 409, 'USERNAME_TAKEN', '该用户名已被注册');

  const id = newId();
  const now = Date.now();
  await c.env.DB.prepare(
    'INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)',
  )
    .bind(id, username, await hashPassword(password), now)
    .run();

  const token = await signJwt({ sub: id, username }, c.env.JWT_SECRET);
  return c.json({ token, user: { id, username } }, 201);
});

/** POST /api/v1/auth/login */
r.post('/login', async (c) => {
  const body = await readJson<{ username?: string; password?: string }>(c);
  const username = (body?.username ?? '').trim();
  const password = body?.password ?? '';
  if (!username || !password) return err(c, 400, 'BAD_CREDENTIALS', '请填写用户名和密码');

  const user = await c.env.DB.prepare(
    'SELECT id, username, password_hash FROM users WHERE username = ?',
  )
    .bind(username)
    .first<UserRow>();

  // 用户名不存在与密码错误返回同一文案，避免账号枚举
  if (!user || !(await verifyPassword(password, user.password_hash))) {
    return err(c, 401, 'LOGIN_FAILED', '用户名或密码错误');
  }

  const token = await signJwt({ sub: user.id, username: user.username }, c.env.JWT_SECRET);
  return c.json({ token, user: { id: user.id, username: user.username } });
});

function validateCredentials(username: string, password: string): string | null {
  if (!isNonEmptyString(username)) return '请填写用户名';
  if (!/^[A-Za-z0-9_@.-]{3,32}$/.test(username)) {
    return '用户名需为 3~32 位字母、数字或 _ @ . -';
  }
  if (password.length < 6) return '密码至少 6 位';
  if (password.length > 128) return '密码过长';
  return null;
}

export default r;
