import type { Context } from 'hono';
import type { ContentfulStatusCode } from 'hono/utils/http-status';

/** 统一错误响应：{ error: { code, message } } */
export function err(
  c: Context,
  status: ContentfulStatusCode,
  code: string,
  message: string,
) {
  return c.json({ error: { code, message } }, status);
}

/** 读取并校验 JSON body */
export async function readJson<T = Record<string, unknown>>(c: Context): Promise<T | null> {
  try {
    const body = await c.req.json<T>();
    return body ?? null;
  } catch {
    return null;
  }
}

export function isNonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.trim().length > 0;
}

export function clampInt(v: unknown, min: number, max: number, fallback: number): number {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}
