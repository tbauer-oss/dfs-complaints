export const config = { runtime: 'nodejs' };

import { redis } from '../_lib/redis.js';
import { safeHandler } from '../_lib/http.js';

function isAdmin(req) {
  const expected = String(process.env.ADMIN_SECRET || '').trim();
  const provided = String(req.headers?.['x-admin-secret'] || req.headers?.['X-Admin-Secret'] || '').trim();
  return !!expected && provided === expected;
}

function getDbTarget() {
  const value = String(process.env.DATABASE_URL || '').trim();
  if (!value) return '';
  try {
    const parsed = new URL(value);
    const host = parsed.hostname || '';
    const port = parsed.port || '5432';
    const database = (parsed.pathname || '').replace(/^\//, '') || '';
    return `${host}:${port}/${database}`;
  } catch {
    return '';
  }
}

async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'method not allowed' });
  }

  if (!isAdmin(req)) {
    return res.status(401).json({ code: 'UNAUTHORIZED', message: 'Unauthorized' });
  }

  const dbTarget = getDbTarget();
  const hasDatabaseUrl = !!String(process.env.DATABASE_URL || '').trim();

  const pingKey = `dfs:diag:ping:${Date.now()}`;
  const started = Date.now();
  const kvPing = { ok: false, ms: 0 };

  try {
    await redis.set(pingKey, 'ok', { ex: 30 });
    await redis.get(pingKey);
    await redis.del(pingKey);
    kvPing.ok = true;
    kvPing.ms = Date.now() - started;
  } catch (err) {
    kvPing.ok = false;
    kvPing.ms = Date.now() - started;
    kvPing.error = err?.code ? `${err.code}:${err.message || ''}` : String(err?.message || err);
  }

  const sampleKeys = {};
  try {
    sampleKeys.repsAll = !!(await redis.get('dfs:reps:all'));
    sampleKeys.roles = !!(await redis.get('dfs:roles'));
    sampleKeys.users = !!(await redis.get('dfs:users'));
  } catch (err) {
    sampleKeys.error = err?.code || err?.message || 'STORE_UNAVAILABLE';
  }

  return res.status(200).json({
    ok: true,
    hasDatabaseUrl,
    dbTarget,
    kvPing,
    sampleKeys,
  });
}

export default safeHandler(handler, { route: '/api/admin/diag-store' });
