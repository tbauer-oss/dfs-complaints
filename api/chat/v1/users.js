// /api/chat/v1/users.js
export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, setCors } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { redis } from '../../_lib/redis.js';
import { createTrackedRedis, logRedisUsage } from './_lib/redisTracker.js';
import { searchActiveUsers } from './_lib/store.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { write: false });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  const { client, counters } = createTrackedRedis(redis);

  try {
    const query = req.query?.query?.toString() || '';
    const limit = Number(req.query?.limit || 50);
    const users = await searchActiveUsers(client, query, limit);
    logRedisUsage('[chat/v1/users] read-only', counters, { users: users.length });
    return ok(res, { ok: true, users });
  } catch (err) {
    console.error('[chat/v1/users] error', err);
    return bad(res, 'server error', 500);
  }
}
