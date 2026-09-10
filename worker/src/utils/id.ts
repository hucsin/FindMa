import { LIMITS } from '../config';

const encoder = new TextEncoder();

/** uint8 -> base64url（无 padding） */
export function b64url(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** base64url -> uint8 */
export function b64urlDecode(str: string): Uint8Array {
  const s = str.replace(/-/g, '+').replace(/_/g, '/');
  const pad = s.length % 4 ? '='.repeat(4 - (s.length % 4)) : '';
  const bin = atob(s + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function utf8(s: string): Uint8Array {
  return encoder.encode(s);
}

/** 随机字节 -> 十六进制 */
export function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** 设备 token：32 字节随机 -> 64 位 hex；D1 只存 SHA-256，原文永远留在手机上 */
export function newDeviceToken(): string {
  return toHex(crypto.getRandomValues(new Uint8Array(32)));
}

export function newId(): string {
  return crypto.randomUUID();
}

/**
 * 生成绑定码：8 位、大小写字母+数字去掉易混淆字符（DESIGN 5.4）。
 * 用拒绝采样避免取模偏置。
 */
export function newBindCode(): string {
  const alphabet = LIMITS.bindCodeAlphabet;
  const n = alphabet.length;
  const limit = Math.floor(256 / n) * n; // 256 内可整除的最大边界
  let out = '';
  while (out.length < LIMITS.bindCodeLength) {
    const buf = crypto.getRandomValues(new Uint8Array(LIMITS.bindCodeLength));
    for (const b of buf) {
      if (b >= limit) continue; // 丢弃有偏置的尾部区间
      out += alphabet[b % n];
      if (out.length === LIMITS.bindCodeLength) break;
    }
  }
  return out;
}

/** 归一化绑定码：去空白、转大写（用户手输时容错） */
export function normalizeBindCode(raw: string): string {
  return (raw || '').replace(/\s+/g, '').toUpperCase();
}
