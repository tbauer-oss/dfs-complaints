// /api/diag/kv.js
export const config = { runtime: 'nodejs' };

import { Redis } from '@upstash/redis';

function pickEnv() {
  const url =
    process.env.UPSTASH_REDIS_REST_URL ||
    process.env.UPSTASH_KV_REST_URL ||
    process.env.REDIS_URL || null;

  const token =
    process.env.UPSTASH_REDIS_REST_TOKEN ||
    process.env.UPSTASH_KV_REST_TOKEN ||
    process.env.REDIS_TOKEN || null;

  return { url, token };
}

export default async function handler(_req, res) {
  res.setHeader('Content-Type', 'application/json');
  try {
    const { url, token } = pickEnv();
    if (!url || !token) {
      return res.end(JSON.stringify({
        ok: true,
        useRedis: false,
        reason: 'missing Upstash ENV',
        needed: ['UPSTASH_REDIS_REST_URL','UPSTASH_REDIS_REST_TOKEN']
      }));
    }

    const redis = new Redis({ url, token });
    const t0 = Date.now();
    const pong = await redis.ping();
    const pingMs = Date.now() - t0;

    // optional: Zähle Keys mit unserem Prefix
    const prefix = 'dfs:';
    const keys = await redis.keys(`${prefix}*`);
    const counts = {
      users: keys.filter(k => k.startsWith(`${prefix}user:`)).length,
      pending: keys.filter(k => k.startsWith(`${prefix}pending:`)).length,
      complaints: keys.filter(k => k.startsWith(`${prefix}complaint:`)).length,
      total: keys.length
    };

    return res.end(JSON.stringify({
      ok: true,
      useRedis: true,
      ping: pong,
      pingMs,
      prefix,
      counts
    }));
  } catch (e) {
    res.statusCode = 500;
    return res.end(JSON.stringify({ ok: false, error: e?.message || String(e) }));
  }
}
