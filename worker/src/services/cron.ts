import type { Env } from '../types';
import { effectiveIntervalSec, readConfig } from '../config';
import { alertText, createAlert } from './store';

interface OfflineRow {
  id: string;
  last_seen_at: number | null;
  mode: string;
  normal_interval_sec: number;
  lost_interval_sec: number;
  offline_alerted: number | null;
}

/**
 * 失联检测（DESIGN 6.5 / 6.6）：每小时跑一次。
 * 判定：now - last_seen_at > max(3 × 当前上报间隔, OFFLINE_MIN_SEC) 且未告警过 → OFFLINE。
 * RECOVERED 在 /report 里判定（设备回来说明网络恢复）。
 */
export async function runOfflineScan(env: Env): Promise<{ checked: number; alerted: number }> {
  const cfg = readConfig(env);
  const now = Date.now();

  const rows = await env.DB.prepare(
    `SELECT d.id, d.last_seen_at, s.mode, s.normal_interval_sec, s.lost_interval_sec,
            COALESCE(st.offline_alerted, 0) AS offline_alerted
       FROM devices d
       JOIN device_settings s ON s.device_id = d.id
       LEFT JOIN device_state st ON st.device_id = d.id
      WHERE d.last_seen_at IS NOT NULL`,
  ).all<OfflineRow>();

  let alerted = 0;
  for (const r of rows.results ?? []) {
    if (r.last_seen_at == null) continue;
    if (r.offline_alerted === 1) continue;

    const intervalSec = effectiveIntervalSec(r.mode, r.normal_interval_sec, r.lost_interval_sec);
    const thresholdMs = Math.max(3 * intervalSec, cfg.offlineMinSec) * 1000;
    const silentMs = now - r.last_seen_at;
    if (silentMs <= thresholdMs) continue;

    const t = alertText('OFFLINE', { minutes: silentMs / 60000 });
    await createAlert(env, r.id, { ...t, type: 'OFFLINE', payload: { silentMs, lastSeenAt: r.last_seen_at } });
    await env.DB.prepare(
      `INSERT INTO device_state (device_id, in_fence, fence_initialized, battery_low_alerted, offline_alerted, guard_off_alerted, updated_at)
       VALUES (?, NULL, 0, 0, 1, 0, ?)
       ON CONFLICT(device_id) DO UPDATE SET offline_alerted = 1, updated_at = excluded.updated_at`,
    )
      .bind(r.id, now)
      .run();
    alerted++;
  }

  return { checked: rows.results?.length ?? 0, alerted };
}

/**
 * 轨迹清理（DESIGN 6.6）：每天 03:00 跑一次，删除超过保留期的 locations。
 * 保留期默认 180 天，可用 LOCATION_RETENTION_DAYS 调整。
 */
export async function runCleanup(env: Env): Promise<{ deleted: number }> {
  const cfg = readConfig(env);
  const cutoff = Date.now() - cfg.retentionDays * 86400_000;

  // D1 单条 DELETE 即可；返回 meta.changes 作为清理行数
  const res = await env.DB.prepare('DELETE FROM locations WHERE reported_at < ?').bind(cutoff).run();
  const deleted = Number((res.meta as { changes?: number } | undefined)?.changes ?? 0);

  // 顺带清理已读且超过保留期的告警（避免 alerts 表无限增长）
  await env.DB.prepare('DELETE FROM alerts WHERE read = 1 AND created_at < ?').bind(cutoff).run();

  return { deleted };
}
