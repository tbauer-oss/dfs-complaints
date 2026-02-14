#!/usr/bin/env node
import { redis } from '../api/_lib/redis.js';

const base = process.env.UPSTASH_REDIS_REST_URL || '';
const token = process.env.UPSTASH_REDIS_REST_TOKEN || '';

if (!base || !token) {
  console.log('[migrate_upstash_to_supabase_kv] skipped: UPSTASH env not set');
  process.exit(0);
}

async function call(path, method = 'GET') {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Upstash ${res.status}`);
  const body = await res.json();
  return body.result;
}

async function main() {
  let cursor = '0';
  let total = 0;
  do {
    const r = await call(`/scan/${cursor}?match=${encodeURIComponent('dfs:*')}&count=500`, 'GET');
    cursor = String(r?.[0] ?? '0');
    const keys = Array.isArray(r?.[1]) ? r[1] : [];
    for (const key of keys) {
      const value = await call(`/get/${encodeURIComponent(key)}`, 'GET');
      let parsed = value;
      if (typeof value === 'string') {
        try { parsed = JSON.parse(value); } catch {}
      }
      await redis.set(key, parsed);
      total += 1;
    }
    console.log(`[migrate_upstash_to_supabase_kv] copied batch=${keys.length} total=${total}`);
  } while (cursor !== '0');

  console.log(`[migrate_upstash_to_supabase_kv] done total=${total}`);
}

main().catch((err) => {
  console.error('[migrate_upstash_to_supabase_kv] failed', err.message);
  process.exit(1);
});
