import { b64url, b64urlDecode, toHex, utf8 } from './id';

// ─────────────────────────── SHA-256 ───────────────────────────

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', utf8(input));
  return toHex(new Uint8Array(digest));
}

// ───────────────────── PBKDF2-SHA256（子女端密码） ─────────────────────

const PBKDF2_ITER = 100_000;

async function pbkdf2Bits(password: string, salt: Uint8Array, iter: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', utf8(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: salt as unknown as BufferSource, iterations: iter, hash: 'SHA-256' },
    key,
    256,
  );
  return new Uint8Array(bits);
}

/** 输出格式：pbkdf2$sha256$<iter>$<saltB64url>$<hashB64url> */
export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const bits = await pbkdf2Bits(password, salt, PBKDF2_ITER);
  return `pbkdf2$sha256$${PBKDF2_ITER}$${b64url(salt)}$${b64url(bits)}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = (stored || '').split('$');
  if (parts.length !== 5 || parts[0] !== 'pbkdf2') return false;
  const iter = Number(parts[2]);
  if (!Number.isFinite(iter) || iter <= 0) return false;
  const salt = b64urlDecode(parts[3]);
  const expected = b64urlDecode(parts[4]);
  const actual = await pbkdf2Bits(password, salt, iter);
  return timingSafeEqual(actual, expected);
}

/** 常数时间比较，避免时序侧信道 */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// ───────────────────── JWT（HS256，手写零依赖） ─────────────────────

export interface JwtPayload {
  sub: string; // userId
  username: string;
  iat: number;
  exp: number;
  [k: string]: unknown;
}

const JWT_TTL_SEC = 30 * 24 * 3600; // 30 天

export async function signJwt(
  payload: Record<string, unknown>,
  secret: string,
  ttlSec: number = JWT_TTL_SEC,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(utf8(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const body = b64url(utf8(JSON.stringify({ ...payload, iat: now, exp: now + ttlSec })));
  const data = `${head}.${body}`;
  const sig = await hmac(secret, data);
  return `${data}.${b64url(sig)}`;
}

export async function verifyJwt(token: string, secret: string): Promise<JwtPayload | null> {
  const parts = (token || '').split('.');
  if (parts.length !== 3) return null;
  const data = `${parts[0]}.${parts[1]}`;
  const expected = await hmac(secret, data);
  if (!timingSafeEqual(expected, b64urlDecode(parts[2]))) return null;
  try {
    const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1]))) as JwtPayload;
    if (!payload.exp || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

async function hmac(secret: string, data: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    utf8(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, utf8(data));
  return new Uint8Array(sig);
}

/** 从 "Bearer xxx" 中取 token */
export function parseBearer(header: string | undefined | null): string {
  if (!header) return '';
  const m = /^Bearer\s+(.+)$/i.exec(header.trim());
  return m ? m[1].trim() : '';
}
