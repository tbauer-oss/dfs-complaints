#!/usr/bin/env node
import { query } from '../api/_lib/db.js';

const UPSTASH_URL = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const UPSTASH_TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();

const SCAN_COUNT = 1000;

if (!UPSTASH_URL || !UPSTASH_TOKEN) {
  console.error('[verify_full_migration] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}
if (!process.env.DATABASE_URL) {
  console.error('[verify_full_migration] missing DATABASE_URL');
  process.exit(1);
}

async function upstashScan(cursor) {
  const url = `${UPSTASH_URL}/scan/${encodeURIComponent(cursor)}?match=${encodeURIComponent('*')}&count=${encodeURIComponent(String(SCAN_COUNT))}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` },
  });

  const body = await res.json();
  if (!res.ok || body?.error) {
    throw new Error(body?.error || `scan failed (${res.status})`);
  }

  return body.result;
}

async function countUpstashKeys() {
  let cursor = '0';
  let total = 0;

  do {
    const result = await upstashScan(cursor);
    cursor = String(result?.[0] ?? '0');
    const keys = Array.isArray(result?.[1]) ? result[1] : [];
    total += keys.length;
  } while (cursor !== '0');

  return total;
}

async function countSupabaseKeys() {
  const res = await query('SELECT count(*)::bigint AS total FROM kv_store', []);
  return Number(res.rows?.[0]?.total || 0);
}

async function main() {
  const [upstashTotal, supabaseTotal] = await Promise.all([
    countUpstashKeys(),
    countSupabaseKeys(),
  ]);

  const diff = upstashTotal - supabaseTotal;

  console.log(`[verify_full_migration] upstash_total=${upstashTotal}`);
  console.log(`[verify_full_migration] supabase_total=${supabaseTotal}`);
  console.log(`[verify_full_migration] diff=${diff}`);
}

main().catch((error) => {
  console.error('[verify_full_migration] failed', error?.message || error);
  process.exit(1);
});
