import type { AlertType, DeviceSettingsRow, DeviceStateRow, Env, GeofenceRow } from '../types';
import { LIMITS, effectiveIntervalSec, type AppConfig } from '../config';

// ───────────────────────────── 设备绑定 / 归属 ─────────────────────────────

export interface OwnedDeviceRow {
  id: string;
  name: string;
  avatar: string | null;
  invite_code: string;
  last_seen_at: number | null;
  nickname: string;
}

/** 校验 device 属于该用户，返回设备 + 该用户的称呼；不属于则 null */
export async function getOwnedDevice(
  env: Env,
  userId: string,
  deviceId: string,
): Promise<OwnedDeviceRow | null> {
  return env.DB.prepare(
    `SELECT d.id, d.name, d.avatar, d.invite_code, d.last_seen_at, ud.nickname
       FROM user_devices ud
       JOIN devices d ON d.id = ud.device_id
      WHERE ud.user_id = ? AND ud.device_id = ?`,
  )
    .bind(userId, deviceId)
    .first<OwnedDeviceRow>();
}

// ───────────────────────────── 配置 settings ─────────────────────────────

/** 取设备配置，不存在则按设计默认值补一条 */
export async function getOrCreateSettings(env: Env, deviceId: string, cfg: AppConfig): Promise<DeviceSettingsRow> {
  const existing = await env.DB.prepare('SELECT * FROM device_settings WHERE device_id = ?')
    .bind(deviceId)
    .first<DeviceSettingsRow>();
  if (existing) return existing;

  const now = Date.now();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO device_settings
       (device_id, mode, normal_interval_sec, lost_interval_sec, fence_enabled, settings_ver, synced_ver, updated_at)
     VALUES (?, 'NORMAL', ?, ?, 1, 1, 1, ?)`,
  )
    .bind(deviceId, cfg.defaultNormalIntervalSec, cfg.defaultLostIntervalSec, now)
    .run();

  return (
    (await env.DB.prepare('SELECT * FROM device_settings WHERE device_id = ?')
      .bind(deviceId)
      .first<DeviceSettingsRow>()) ?? {
      device_id: deviceId,
      mode: 'NORMAL',
      normal_interval_sec: cfg.defaultNormalIntervalSec,
      lost_interval_sec: cfg.defaultLostIntervalSec,
      fence_enabled: 1,
      settings_ver: 1,
      synced_ver: 1,
      updated_at: now,
    }
  );
}

// ───────────────────────────── 运行状态 state ─────────────────────────────

export async function getOrCreateState(env: Env, deviceId: string): Promise<DeviceStateRow> {
  const existing = await env.DB.prepare('SELECT * FROM device_state WHERE device_id = ?')
    .bind(deviceId)
    .first<DeviceStateRow>();
  if (existing) return existing;

  const now = Date.now();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO device_state
       (device_id, in_fence, fence_initialized, battery_low_alerted, offline_alerted, guard_off_alerted, updated_at)
     VALUES (?, NULL, 0, 0, 0, 0, ?)`,
  )
    .bind(deviceId, now)
    .run();

  return {
    device_id: deviceId,
    in_fence: null,
    fence_initialized: 0,
    battery_low_alerted: 0,
    offline_alerted: 0,
    guard_off_alerted: 0,
    updated_at: now,
  };
}

// ───────────────────────────── 围栏 ─────────────────────────────

/** 取设备当前生效的围栏（MVP 一个设备一个，取最近更新的） */
export async function getActiveFence(env: Env, deviceId: string): Promise<GeofenceRow | null> {
  return env.DB.prepare(
    `SELECT * FROM geofences WHERE device_id = ? AND enabled = 1 ORDER BY updated_at DESC LIMIT 1`,
  )
    .bind(deviceId)
    .first<GeofenceRow>();
}

// ───────────────────────────── 告警 ─────────────────────────────

export interface AlertInput {
  type: AlertType;
  title: string;
  body: string;
  payload?: unknown;
}

export function alertStatement(
  env: Env,
  deviceId: string,
  a: AlertInput,
  createdAt: number,
) {
  return env.DB.prepare(
    `INSERT INTO alerts (device_id, type, title, body, payload_json, read, created_at)
     VALUES (?, ?, ?, ?, ?, 0, ?)`,
  ).bind(deviceId, a.type, a.title, a.body, a.payload ? JSON.stringify(a.payload) : null, createdAt);
}

/** 不参与 batch 时直接写一条告警 */
export async function createAlert(env: Env, deviceId: string, a: AlertInput): Promise<void> {
  await alertStatement(env, deviceId, a, Date.now()).run();
}

export function alertText(
  type: AlertType,
  extra?: { distanceM?: number | null; battery?: number | null; minutes?: number | null },
): { title: string; body: string } {
  switch (type) {
    case 'OUT_OF_FENCE':
      return {
        title: '老人已走出电子围栏',
        body:
          extra?.distanceM != null
            ? `当前已超出围栏边界约 ${Math.round(extra.distanceM)} 米，请及时关注。`
            : '老人已离开设定的安全范围，请及时关注。',
      };
    case 'BACK_IN_FENCE':
      return { title: '老人已回到电子围栏内', body: '老人已回到设定的安全范围内。' };
    case 'LOW_BATTERY':
      return {
        title: '老人手机电量偏低',
        body:
          extra?.battery != null
            ? `当前电量 ${Math.round(extra.battery)}%，且未在充电，建议提醒老人充电。`
            : '手机电量偏低且未在充电，建议提醒老人充电。',
      };
    case 'OFFLINE':
      return {
        title: '老人设备已失联',
        body:
          extra?.minutes != null
            ? `已超过 ${Math.round(extra.minutes)} 分钟没有收到位置上报，请检查设备与网络。`
            : '长时间未收到位置上报，请检查设备与网络。',
      };
    case 'RECOVERED':
      return { title: '老人设备已恢复上报', body: '设备重新开始上报位置，失联状态已解除。' };
    case 'GUARD_OFF':
      return {
        title: '流量守护未生效',
        body: '设备当前处于蜂窝网络，但网络守护 VPN 未运行，其他 App 可能在消耗老人的流量。',
      };
    default:
      return { title: '告警', body: '' };
  }
}

/** 计算设备当前生效的上报间隔（秒） */
export function intervalOf(s: DeviceSettingsRow): number {
  return effectiveIntervalSec(s.mode, s.normal_interval_sec, s.lost_interval_sec);
}

/** 配置同步状态：待设备同步 / 已生效 */
export function syncStateOf(s: Pick<DeviceSettingsRow, 'settings_ver' | 'synced_ver'>): 'synced' | 'pending' {
  return s.synced_ver >= s.settings_ver ? 'synced' : 'pending';
}

export { LIMITS };
