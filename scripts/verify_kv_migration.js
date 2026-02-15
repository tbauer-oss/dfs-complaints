#!/usr/bin/env node
import { query } from '../api/_lib/db.js';

const BASE = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();
const DATABASE_URL = String(process.env.DATABASE_URL || '').trim();
const PATTERNS = String(process.env.MIGRATE_PATTERNS || 'dfs:*,chat:*')
  .split(',')
  .map((item) => item.trim())
  .filter(Boolean);
const SCAN_COUNT = Math.max(1, Number(process.env.SCAN_COUNT || 1000));

if (!BASE || !TOKEN) {
  console.error('[verify_kv_migration] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}
if (!DATABASE_URL) {
  console.error('[verify_kv_migration] missing DATABASE_URL');
  process.exit(1);
}

async function upstashScan(cursor, match) {
  const url = `${BASE}/scan/${encodeURIComponent(String(cursor))}?match=${encodeURIComponent(match)}&count=${encodeURIComponent(String(SCAN_COUNT))}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}` } });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body?.error) throw new Error(body?.error || `scan failed (${res.status})`);
  return body?.result;
}

async function countUpstash(pattern) {
  let cursor = '0';
  let count = 0;
  do {
    const result = await upstashScan(cursor, pattern);
    cursor = String(result?.[0] ?? '0');
    const keys = Array.isArray(result?.[1]) ? result[1] : [];
    count += keys.length;
  } while (cursor !== '0');
  return count;
}

async function main() {
  const upstashByPattern = {};
  for (const pattern of PATTERNS) {
    upstashByPattern[pattern] = await countUpstash(pattern);
  }
  const upstashTotal = Object.values(upstashByPattern).reduce((sum, n) => sum + n, 0);

  const sqlLikeClauses = PATTERNS.map((pattern, index) => `k LIKE $${index + 1}`).join(' OR ');
  const likeParams = PATTERNS.map((pattern) => pattern.replace(/\*/g, '%'));

  const totalResult = await query(
    `SELECT COUNT(*)::int AS total
     FROM kv_store
     WHERE ${sqlLikeClauses}`,
    likeParams,
  );
  const supabaseTotal = totalResult.rows?.[0]?.total || 0;

  const pfxResult = await query(
    `SELECT split_part(k, ':', 1) AS pfx, COUNT(*)::int AS count
     FROM kv_store
     GROUP BY 1
     ORDER BY 2 DESC`,
    [],
  );

  console.log('[verify_kv_migration] totals', {
    upstash_total: upstashTotal,
    supabase_total: supabaseTotal,
    diff: upstashTotal - supabaseTotal,
    upstash_by_pattern: upstashByPattern,
  });

  console.log('[verify_kv_migration] supabase_prefix_breakdown');
  for (const row of pfxResult.rows || []) {
    console.log(`  ${row.pfx}: ${row.count}`);
  }
}

main().catch((error) => {
  console.error('[verify_kv_migration] failed', error.message);
  process.exit(1);
});
