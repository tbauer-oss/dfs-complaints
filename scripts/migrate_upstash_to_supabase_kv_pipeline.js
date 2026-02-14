#!/usr/bin/env node
import { createKvRedisCompat } from '../api/_lib/kvStore.js';

const UPSTASH_URL = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const UPSTASH_TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();
const SCAN_COUNT = Math.max(1, Number(process.env.UPSTASH_SCAN_COUNT || 1000));
const PIPELINE_BATCH = Math.max(1, Number(process.env.UPSTASH_PIPELINE_BATCH || 100));

if (!UPSTASH_URL || !UPSTASH_TOKEN) {
  console.error('[migrate_upstash_to_supabase_kv_pipeline] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}
if (!String(process.env.DATABASE_URL || '').trim()) {
  console.error('[migrate_upstash_to_supabase_kv_pipeline] missing DATABASE_URL');
  process.exit(1);
}

async function upstashScan(cursor) {
  const url = `${UPSTASH_URL}/scan/${encodeURIComponent(cursor)}?match=${encodeURIComponent('dfs:*')}&count=${encodeURIComponent(String(SCAN_COUNT))}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` } });
  if (!res.ok) throw new Error(`scan failed (${res.status})`);
  const body = await res.json();
  if (body?.error) throw new Error(body.error);
  return body?.result;
}

async function upstashPipeline(commands) {
  const res = await fetch(`${UPSTASH_URL}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${UPSTASH_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(commands),
  });
  if (!res.ok) throw new Error(`pipeline failed (${res.status})`);
  const body = await res.json();
  if (body?.error) throw new Error(body.error);
  return body?.result;
}

function parseMaybeJson(raw) {
  if (typeof raw !== 'string') return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

async function main() {
  const redis = createKvRedisCompat();
  const stats = { scanned: 0, migrated: 0, jsonParsed: 0, rawStrings: 0, nullValues: 0 };

  let cursor = '0';
  do {
    const scan = await upstashScan(cursor);
    cursor = String(scan?.[0] ?? '0');
    const keys = Array.isArray(scan?.[1]) ? scan[1] : [];
    stats.scanned += keys.length;

    for (let i = 0; i < keys.length; i += PIPELINE_BATCH) {
      const batch = keys.slice(i, i + PIPELINE_BATCH);
      const commands = batch.map((key) => ['GET', key]);
      const results = await upstashPipeline(commands);

      for (let index = 0; index < batch.length; index += 1) {
        const key = batch[index];
        const item = Array.isArray(results) ? results[index] : null;
        if (!item || item.error) {
          throw new Error(`pipeline GET failed for key=${key}: ${item?.error || 'missing response'}`);
        }

        const value = item.result;
        if (value === null || value === undefined) {
          stats.nullValues += 1;
          continue;
        }

        const parsed = parseMaybeJson(value);
        if (typeof value === 'string' && typeof parsed !== 'string') stats.jsonParsed += 1;
        else stats.rawStrings += 1;

        await redis.set(key, parsed);
        stats.migrated += 1;
      }
    }

    console.log(`[migrate_upstash_to_supabase_kv_pipeline] scanned=${stats.scanned} migrated=${stats.migrated} cursor=${cursor}`);
  } while (cursor !== '0');

  console.log('[migrate_upstash_to_supabase_kv_pipeline] done', stats);
}

main().catch((err) => {
  console.error('[migrate_upstash_to_supabase_kv_pipeline] failed', err.message);
  process.exit(1);
});

