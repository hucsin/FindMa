import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { AppEnv, Env } from './types';
import { err } from './http';
import deviceRoutes from './routes/device';
import reportRoutes from './routes/report';
import authRoutes from './routes/auth';
import devicesRoutes from './routes/devices';
import alertsRoutes from './routes/alerts';
import { runCleanup, runOfflineScan } from './services/cron';

const app = new Hono<AppEnv>();

app.use('*', cors({ origin: '*', allowHeaders: ['Content-Type', 'Authorization', 'X-Device-Token'] }));

app.get('/', (c) => c.text('FindMa API is running.'));
app.get('/health', (c) => c.json({ ok: true, serverTs: Date.now() }));

// JWT_SECRET 未配置时直接给出可操作的报错（避免部署后才在登录时才发现）
app.use('/api/*', async (c, next) => {
  if (!c.env.JWT_SECRET) {
    return err(c, 500, 'SERVER_MISCONFIGURED', '未配置 JWT_SECRET，请执行 npm run secret:jwt');
  }
  await next();
});

const api = new Hono<AppEnv>();
api.route('/device', deviceRoutes);   // register / rebind-code
api.route('/auth', authRoutes);       // register / login
api.route('/', reportRoutes);         // POST /report（DESIGN 路径为 /api/v1/report）
api.route('/devices', devicesRoutes); // 我的设备 / 绑定 / 资料 / 摘要 / 轨迹 / 设置 / 围栏
api.route('/alerts', alertsRoutes);   // 告警列表 / 标记已读

app.route('/api/v1', api);

app.notFound((c) => err(c, 404, 'NOT_FOUND', `接口不存在：${new URL(c.req.url).pathname}`));

app.onError((e, c) => {
  console.error('[findma] unhandled error:', e);
  return err(c, 500, 'INTERNAL_ERROR', '服务器内部错误');
});

export default {
  fetch: app.fetch,

  /**
   * Cron Triggers（DESIGN 6.6）
   *  "0 * * * *"  每小时 → 失联检测
   *  "0 3 * * *"  每天 03:00 → 轨迹清理
   */
  async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    const job = controller.cron === '0 3 * * *' ? runCleanup(env) : runOfflineScan(env);
    ctx.waitUntil(
      job
        .then((r) => console.log('[findma] cron', controller.cron, JSON.stringify(r)))
        .catch((e) => console.error('[findma] cron failed', controller.cron, e)),
    );
  },
};
