import type { AlertType, Env, ReportPoint } from '../types';
import { LIMITS, readConfig } from '../config';
import { clampInt } from '../http';
import { evaluateFence, isValidLatLng } from '../utils/geo';
import {
  alertStatement,
  alertText,
  getActiveFence,
  getOrCreateSettings,
  getOrCreateState,
  intervalOf,
} from './store';

export interface ReportBody {
  settingsVer?: number;
  netType?: string;
  vpnActive?: boolean;
  appVer?: string;
  points?: ReportPoint[];
}

interface AlertDraft {
  type: AlertType;
  title: string;
  body: string;
  payload?: unknown;
}

export interface ReportResult {
  serverTs: number;
  settings: {
    ver: number;
    mode: string;
    reportIntervalSec: number;
    normalIntervalSec: number;
    lostIntervalSec: number;
    fenceEnabled: boolean;
  };
  accepted: number;
  rejected: number;
  mode: string;
}

/**
 * 上报主流程（DESIGN 6.4 / 9-①）：
 *   逐点入库 → 围栏判定 → 状态翻转生成告警 → 低电/守护失效判定 → 更新 last_seen → 下发最新配置
 * 所有写操作合并为一个 D1 batch（同一事务提交，避免半写）。
 */
export async function handleReport(
  env: Env,
  deviceId: string,
  body: ReportBody,
): Promise<ReportResult> {
  const cfg = readConfig(env);
  const now = Date.now();

  const settings = await getOrCreateSettings(env, deviceId, cfg);
  const state = await getOrCreateState(env, deviceId);
  const fence = settings.fence_enabled === 1 ? await getActiveFence(env, deviceId) : null;
  const fenceModeOn = settings.mode === 'WATCH' || settings.mode === 'LOST';

  const { points, rejected } = normalizePoints(body.points ?? []);

  // ── 可变状态机（围栏 / 告警去重标记）────────────────────────────────────
  let inFence = state.in_fence;
  let fenceInitialized = state.fence_initialized === 1;
  let batteryLowAlerted = state.battery_low_alerted === 1;
  let guardOffAlerted = state.guard_off_alerted === 1;
  let offlineAlerted = state.offline_alerted === 1;

  const stmts: D1PreparedStatement[] = [];
  const alerts: AlertDraft[] = [];

  const netType = typeof body.netType === 'string' ? body.netType : null;
  const vpnActive = body.vpnActive === true ? 1 : body.vpnActive === false ? 0 : null;

  for (const p of points) {
    const evalRes = evaluateFence({
      fence,
      lat: p.lat,
      lng: p.lng,
      accuracy: p.acc ?? null,
      prevInFence: inFence,
      fenceInitialized,
      bufferM: cfg.fenceBufferM,
      accuracyGateM: cfg.fenceAccuracyGateM,
    });

    // 首次建立围栏状态、且建立时人已在界外 → 立即告警（DESIGN 6.4-5）
    const firstFix = !fenceInitialized && evalRes.judged;
    if (fenceModeOn) {
      if (firstFix && evalRes.inFence === 0) {
        const t = alertText('OUT_OF_FENCE', { distanceM: evalRes.distanceM });
        alerts.push({ ...t, type: 'OUT_OF_FENCE', payload: { lat: p.lat, lng: p.lng, first: true } });
      } else if (evalRes.transition === 'out') {
        const t = alertText('OUT_OF_FENCE', { distanceM: evalRes.distanceM });
        alerts.push({ ...t, type: 'OUT_OF_FENCE', payload: { lat: p.lat, lng: p.lng } });
      } else if (evalRes.transition === 'in') {
        const t = alertText('BACK_IN_FENCE');
        alerts.push({ ...t, type: 'BACK_IN_FENCE', payload: { lat: p.lat, lng: p.lng } });
      }
    }

    if (evalRes.judged && evalRes.inFence != null) {
      inFence = evalRes.inFence;
      fenceInitialized = true;
    }
    // 未判定的点（无围栏 / 精度不足）在轨迹里记为 NULL，设备状态保持（DESIGN 6.4-1）
    const storedInFence = evalRes.judged ? evalRes.inFence : null;

    stmts.push(
      env.DB.prepare(
        `INSERT INTO locations
           (device_id, lat, lng, accuracy, speed, bearing, battery, charging,
            provider, net_type, vpn_active, in_fence, dev_ts, reported_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        deviceId,
        p.lat,
        p.lng,
        p.acc ?? null,
        p.speed ?? null,
        p.bearing ?? null,
        p.batt ?? null,
        p.charging == null ? null : p.charging ? 1 : 0,
        p.provider ?? null,
        netType,
        vpnActive,
        storedInFence,
        p.devTs ?? null,
        now,
      ),
    );
  }

  // ── 低电告警（去重：每个充电周期只告一次）──────────────────────────────
  const lastBatt = [...points].reverse().find((p) => p.batt != null) ?? null;
  if (lastBatt && lastBatt.batt != null) {
    const charging = lastBatt.charging === true;
    if (charging || lastBatt.batt > cfg.lowBatteryThreshold) {
      batteryLowAlerted = false;
    } else if (!batteryLowAlerted) {
      const t = alertText('LOW_BATTERY', { battery: lastBatt.batt });
      alerts.push({ ...t, type: 'LOW_BATTERY', payload: { battery: lastBatt.batt } });
      batteryLowAlerted = true;
    }
  }

  // ── 守护失效告警（蜂窝网络下 VPN 未生效）────────────────────────────────
  if (netType === 'cellular' && vpnActive === 0) {
    if (!guardOffAlerted) {
      const t = alertText('GUARD_OFF');
      alerts.push({ ...t, type: 'GUARD_OFF', payload: { netType, vpnActive: false } });
      guardOffAlerted = true;
    }
  } else if (netType) {
    guardOffAlerted = false;
  }

  // ── 失联恢复 ────────────────────────────────────────────────────────────
  if (offlineAlerted) {
    const t = alertText('RECOVERED');
    alerts.push({ ...t, type: 'RECOVERED', payload: null });
    offlineAlerted = false;
  }

  // ── 合并写入 ────────────────────────────────────────────────────────────
  for (const a of alerts) stmts.push(alertStatement(env, deviceId, a, now));

  stmts.push(
    env.DB.prepare(
      `INSERT INTO device_state
         (device_id, in_fence, fence_initialized, battery_low_alerted, offline_alerted, guard_off_alerted, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(device_id) DO UPDATE SET
         in_fence = excluded.in_fence,
         fence_initialized = excluded.fence_initialized,
         battery_low_alerted = excluded.battery_low_alerted,
         offline_alerted = excluded.offline_alerted,
         guard_off_alerted = excluded.guard_off_alerted,
         updated_at = excluded.updated_at`,
    ).bind(
      deviceId,
      inFence,
      fenceInitialized ? 1 : 0,
      batteryLowAlerted ? 1 : 0,
      offlineAlerted ? 1 : 0,
      guardOffAlerted ? 1 : 0,
      now,
    ),
  );

  stmts.push(
    env.DB.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?').bind(now, deviceId),
  );

  // 设备回传的 settingsVer = 它已应用到的版本（DESIGN 5.2：幂等回传）
  const clientVer = clampInt(body.settingsVer, 0, settings.settings_ver, 0);
  if (clientVer > settings.synced_ver) {
    stmts.push(
      env.DB.prepare('UPDATE device_settings SET synced_ver = ? WHERE device_id = ? AND synced_ver < ?')
        .bind(clientVer, deviceId, clientVer),
    );
  }

  await env.DB.batch(stmts);

  return {
    serverTs: now,
    settings: {
      ver: settings.settings_ver,
      mode: settings.mode,
      reportIntervalSec: intervalOf(settings),
      normalIntervalSec: settings.normal_interval_sec,
      lostIntervalSec: settings.lost_interval_sec,
      fenceEnabled: settings.fence_enabled === 1,
    },
    accepted: points.length,
    rejected,
    mode: settings.mode,
  };
}

/** 清洗上报点：丢弃非法点，按 devTs 升序排列，超出上限时保留最新的 N 条 */
function normalizePoints(raw: ReportPoint[]): { points: ReportPoint[]; rejected: number } {
  let rejected = 0;
  const list: ReportPoint[] = [];

  for (const p of raw) {
    if (!p || !isValidLatLng(p.lat, p.lng)) {
      rejected++;
      continue;
    }
    const devTs = Number(p.devTs);
    list.push({
      lat: p.lat,
      lng: p.lng,
      acc: finiteOrNull(p.acc),
      speed: finiteOrNull(p.speed),
      bearing: finiteOrNull(p.bearing),
      batt: finiteOrNull(p.batt),
      charging: p.charging === true,
      provider: typeof p.provider === 'string' ? p.provider.slice(0, 16) : null,
      // 防设备时钟漂移：未来时间一律按服务器时间处理
      devTs: Number.isFinite(devTs) && devTs > 0 && devTs < Date.now() + 86400_000 ? devTs : null,
    });
  }

  if (list.length > 1) {
    list.sort((a, b) => (a.devTs ?? 0) - (b.devTs ?? 0));
  }
  if (list.length > LIMITS.maxPointsPerReport) {
    rejected += list.length - LIMITS.maxPointsPerReport;
    list.splice(0, list.length - LIMITS.maxPointsPerReport);
  }
  return { points: list, rejected };
}

function finiteOrNull(v: unknown): number | null {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
