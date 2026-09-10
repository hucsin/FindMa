import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { err, readJson } from '../http';
import { deviceAuth } from '../middleware/deviceAuth';
import { handleReport, type ReportBody } from '../services/report';

const r = new Hono<AppEnv>();

/**
 * POST /api/v1/report
 * 老人端定时上报（含离线补传的批量点），响应携带最新配置（DESIGN 6.2 / 9-①）。
 */
r.post('/report', deviceAuth, async (c) => {
  const deviceId = c.get('deviceId');
  const body = await readJson<ReportBody>(c);
  if (!body || typeof body !== 'object') {
    return err(c, 400, 'BAD_JSON', '请求体必须是合法 JSON');
  }
  if (body.points != null && !Array.isArray(body.points)) {
    return err(c, 400, 'BAD_POINTS', 'points 必须是数组');
  }

  const result = await handleReport(c.env, deviceId, body);
  return c.json({
    serverTs: result.serverTs,
    settings: result.settings,
    accepted: result.accepted,
    rejected: result.rejected,
  });
});

export default r;
