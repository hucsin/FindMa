import type { Env } from './types';

/** 把 Env 里的字符串 vars 收敛成带默认值的数字配置，业务代码统一从这里取。 */
export interface AppConfig {
  defaultNormalIntervalSec: number;
  defaultLostIntervalSec: number;
  fenceBufferM: number;
  fenceAccuracyGateM: number;
  lowBatteryThreshold: number;
  offlineMinSec: number;
  retentionDays: number;
  maxAvatarBytes: number;
}

export function readConfig(env: Env): AppConfig {
  return {
    defaultNormalIntervalSec: num(env.DEFAULT_NORMAL_INTERVAL_SEC, 1200),
    defaultLostIntervalSec: num(env.DEFAULT_LOST_INTERVAL_SEC, 60),
    fenceBufferM: num(env.FENCE_BUFFER_M, 50),
    fenceAccuracyGateM: num(env.FENCE_ACCURACY_GATE_M, 150),
    lowBatteryThreshold: num(env.LOW_BATTERY_THRESHOLD, 20),
    offlineMinSec: num(env.OFFLINE_MIN_SEC, 7200),
    retentionDays: num(env.LOCATION_RETENTION_DAYS, 180),
    maxAvatarBytes: num(env.MAX_AVATAR_BYTES, 102400),
  };
}

function num(v: string | undefined, fallback: number): number {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/** 业务约束（与 DESIGN 5.1 / 5.4 对齐） */
export const LIMITS = {
  /** 上报批量点上限，防单次请求过大 */
  maxPointsPerReport: 500,
  /** 上报间隔下限，防止把老人手机打爆 */
  minIntervalSec: 15,
  maxIntervalSec: 86400,
  /** 历史轨迹单次返回上限 */
  maxTrackPoints: 2000,
  /** 告警列表单次返回上限 */
  maxAlerts: 200,
  /** 绑定码长度与字符集（去掉 0/O/1/I 等易混淆字符） */
  bindCodeLength: 8,
  bindCodeAlphabet: 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
} as const;

/** 按当前模式取生效的上报间隔 */
export function effectiveIntervalSec(
  mode: string,
  normalIntervalSec: number,
  lostIntervalSec: number,
): number {
  return mode === 'LOST' ? lostIntervalSec : normalIntervalSec;
}
