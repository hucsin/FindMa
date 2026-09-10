/** 全局类型定义（Env 绑定 / 请求上下文变量） */

export interface Env {
  DB: D1Database;
  JWT_SECRET: string;

  // vars（均为字符串，读取时用 config.ts 转数字）
  DEFAULT_NORMAL_INTERVAL_SEC?: string;
  DEFAULT_LOST_INTERVAL_SEC?: string;
  FENCE_BUFFER_M?: string;
  FENCE_ACCURACY_GATE_M?: string;
  LOW_BATTERY_THRESHOLD?: string;
  OFFLINE_MIN_SEC?: string;
  LOCATION_RETENTION_DAYS?: string;
  MAX_AVATAR_BYTES?: string;
}

/** Hono 的 Bindings + Variables 组合类型 */
export type AppEnv = {
  Bindings: Env;
  Variables: {
    /** 老人端鉴权后注入 */
    deviceId: string;
    /** 子女端鉴权后注入 */
    userId: string;
  };
};

export type Mode = 'NORMAL' | 'WATCH' | 'LOST';

/** device_settings 行 */
export interface DeviceSettingsRow {
  device_id: string;
  mode: Mode;
  normal_interval_sec: number;
  lost_interval_sec: number;
  fence_enabled: number;
  settings_ver: number;
  synced_ver: number;
  updated_at: number;
}

/** device_state 行 */
export interface DeviceStateRow {
  device_id: string;
  in_fence: number | null;
  fence_initialized: number;
  battery_low_alerted: number;
  offline_alerted: number;
  guard_off_alerted: number;
  updated_at: number;
}

/** geofences 行 */
export interface GeofenceRow {
  id: string;
  device_id: string;
  name: string;
  type: 'circle' | 'polygon';
  center_lat: number | null;
  center_lng: number | null;
  radius_m: number | null;
  polygon_json: string | null;
  enabled: number;
  updated_at: number;
}

/** 老人端上报的单点 */
export interface ReportPoint {
  lat: number;
  lng: number;
  acc?: number | null;
  speed?: number | null;
  bearing?: number | null;
  batt?: number | null;
  charging?: boolean | null;
  provider?: string | null;
  devTs?: number | null;
}

export type AlertType =
  | 'OUT_OF_FENCE'
  | 'BACK_IN_FENCE'
  | 'LOW_BATTERY'
  | 'OFFLINE'
  | 'RECOVERED'
  | 'GUARD_OFF';
