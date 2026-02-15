#!/usr/bin/env node
import { redis } from '../api/_lib/redis.js';

const BASE = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();
const DATABASE_URL = String(process.env.DATABASE_URL || '').trim();

const PATTERNS = String(process.env.MIGRATE_PATTERNS || 'dfs:*,chat:*')
  .split(',')
  .map((item) => item.trim())
  .filter(Boolean);

const SCAN_COUNT = Math.max(1, Number(process.env.SCAN_COUNT || 1000));
const PIPELINE_BATCH = Math.max(1, Number(process.env.PIPELINE_BATCH || 100));
const TTL_MODE = String(process.env.TTL_MODE || 'none').trim().toLowerCase();
const TTL_PIPELINE_BATCH = Math.max(1, Number(process.env.TTL_PIPELINE_BATCH || 100));
const DRY_RUN = String(process.env.DRY_RUN || '') === '1';
const STOP_AFTER = Number(process.env.STOP_AFTER || 0);

function parseStartCursorMap(raw) {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    throw new Error('START_CURSOR_MAP must be valid JSON object');
  }
}

const START_CURSOR_MAP = parseStartCursorMap(process.env.START_CURSOR_MAP || '');

if (!BASE || !TOKEN) {
  console.error('[migrate_upstash_to_supabase_kv_full] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}
if (!DATABASE_URL) {
  console.error('[migrate_upstash_to_supabase_kv_full] missing DATABASE_URL');
  process.exit(1);
}
if (!PATTERNS.length) {
  console.error('[migrate_upstash_to_supabase_kv_full] no patterns provided via MIGRATE_PATTERNS');
  process.exit(1);
}
if (!['none', 'best-effort'].includes(TTL_MODE)) {
  console.error('[migrate_upstash_to_supabase_kv_full] TTL_MODE must be one of: none, best-effort');
  process.exit(1);
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function isRateLimitError(message = '') {
  return /max requests limit exceeded/i.test(message);
}

function normalizeUpstashFailure(err, fallback) {
  const message = String(err?.message || fallback || 'Upstash request failed');
  const e = new Error(message);
  e.isRateLimited = isRateLimitError(message);
  return e;
}

async function withRetry(fn, label) {
  const maxRetries = 3;
  let attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (error) {
      const normalized = normalizeUpstashFailure(error, `${label} failed`);
      if (normalized.isRateLimited) throw normalized;
      if (attempt >= maxRetries) throw normalized;
      const delay = 250 * (2 ** attempt);
      attempt += 1;
      console.warn(`[migrate_upstash_to_supabase_kv_full] retrying ${label} attempt=${attempt} delayMs=${delay}`);
      await wait(delay);
    }
  }
}

async function upstashScan(cursor, match, count) {
  return withRetry(async () => {
    const url = `${BASE}/scan/${encodeURIComponent(String(cursor))}?match=${encodeURIComponent(match)}&count=${encodeURIComponent(String(count))}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}` } });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || body?.error) {
      throw new Error(body?.error || `scan failed (${res.status})`);
    }
    return body?.result;
  }, `scan:${match}`);
}

async function upstashPipeline(commands) {
  return withRetry(async () => {
    const res = await fetch(`${BASE}/pipeline`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(commands),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || body?.error) {
      throw new Error(body?.error || `pipeline failed (${res.status})`);
    }
    return body?.result;
  }, 'pipeline');
}

async function pipelineGet(keys) {
  if (!keys.length) return [];
  return upstashPipeline(keys.map((key) => ['GET', key]));
}

async function pipelineTtl(keys) {
  if (!keys.length) return [];
  return upstashPipeline(keys.map((key) => ['TTL', key]));
}

function parseMaybeJson(raw) {
  if (typeof raw !== 'string') return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

function parseTtlResult(item) {
  const ttl = Number(item?.result);
  if (!Number.isFinite(ttl) || ttl <= 0) return null;
  return Math.floor(ttl);
}

function printResumeCursorMap(patternCursorMap) {
  console.log('[migrate_upstash_to_supabase_kv_full] resume_cursor_map', JSON.stringify(patternCursorMap));
}

async function processPattern(pattern, state, globalStats) {
  let cursor = String(START_CURSOR_MAP[pattern] ?? '0');
  state.cursorMap[pattern] = cursor;

  do {
    const scanResult = await upstashScan(cursor, pattern, SCAN_COUNT);
    const nextCursor = String(scanResult?.[0] ?? '0');
    const keys = Array.isArray(scanResult?.[1]) ? scanResult[1] : [];

    state.patternStats[pattern].scanned += keys.length;
    globalStats.scanned += keys.length;

    for (let i = 0; i < keys.length; i += PIPELINE_BATCH) {
      const batch = keys.slice(i, i + PIPELINE_BATCH);
      const values = await pipelineGet(batch);

      let ttlResults = null;
      if (TTL_MODE === 'best-effort' && !DRY_RUN) {
        ttlResults = [];
        for (let t = 0; t < batch.length; t += TTL_PIPELINE_BATCH) {
          const ttlBatch = batch.slice(t, t + TTL_PIPELINE_BATCH);
          const ttlChunk = await pipelineTtl(ttlBatch);
          ttlResults.push(...(Array.isArray(ttlChunk) ? ttlChunk : []));
        }
      }

      for (let index = 0; index < batch.length; index += 1) {
        const key = batch[index];
        const item = Array.isArray(values) ? values[index] : null;
        if (!item || item.error) {
          throw new Error(`GET failed for key=${key}: ${item?.error || 'missing response'}`);
        }

        const raw = item.result ?? null;
        if (raw === null) {
          state.patternStats[pattern].nullValues += 1;
          globalStats.nullValues += 1;
          continue;
        }

        const parsed = parseMaybeJson(raw);
        if (!DRY_RUN) {
          if (TTL_MODE === 'best-effort') {
            const ttl = parseTtlResult(ttlResults?.[index]);
            if (ttl) await redis.set(key, parsed, { ex: ttl });
            else await redis.set(key, parsed);
          } else {
            await redis.set(key, parsed);
          }
        }

        state.patternStats[pattern].written += 1;
        globalStats.written += 1;

        if (STOP_AFTER > 0 && globalStats.written >= STOP_AFTER) {
          state.cursorMap[pattern] = nextCursor;
          throw new Error('__STOP_AFTER__');
        }
      }
    }

    cursor = nextCursor;
    state.cursorMap[pattern] = cursor;

    console.log(
      `[migrate_upstash_to_supabase_kv_full] pattern=${pattern} cursor=${cursor} scanned=${state.patternStats[pattern].scanned} written=${state.patternStats[pattern].written} totalScanned=${globalStats.scanned} totalWritten=${globalStats.written}`,
    );
  } while (cursor !== '0');
}

async function main() {
  const state = {
    cursorMap: Object.fromEntries(PATTERNS.map((pattern) => [pattern, String(START_CURSOR_MAP[pattern] ?? '0')])),
    patternStats: Object.fromEntries(PATTERNS.map((pattern) => [pattern, { scanned: 0, written: 0, nullValues: 0 }])),
  };
  const globalStats = { scanned: 0, written: 0, nullValues: 0, dryRun: DRY_RUN, ttlMode: TTL_MODE };

  console.log('[migrate_upstash_to_supabase_kv_full] starting', {
    patterns: PATTERNS,
    scanCount: SCAN_COUNT,
    pipelineBatch: PIPELINE_BATCH,
    ttlMode: TTL_MODE,
    dryRun: DRY_RUN,
    stopAfter: STOP_AFTER || null,
  });

  try {
    for (const pattern of PATTERNS) {
      await processPattern(pattern, state, globalStats);
    }
    console.log('[migrate_upstash_to_supabase_kv_full] done', globalStats);
    printResumeCursorMap(state.cursorMap);
  } catch (error) {
    if (String(error?.message || '') === '__STOP_AFTER__') {
      console.warn('[migrate_upstash_to_supabase_kv_full] STOP_AFTER reached; exiting gracefully');
      console.log('[migrate_upstash_to_supabase_kv_full] partial', globalStats);
      printResumeCursorMap(state.cursorMap);
      return;
    }

    const normalized = normalizeUpstashFailure(error, '[migrate_upstash_to_supabase_kv_full] failed');
    if (normalized.isRateLimited) {
      console.error('[migrate_upstash_to_supabase_kv_full] aborted: Upstash rate limit reached');
      printResumeCursorMap(state.cursorMap);
      process.exit(2);
    }

    console.error('[migrate_upstash_to_supabase_kv_full] failed', normalized.message);
    printResumeCursorMap(state.cursorMap);
    process.exit(1);
  }
}

main();
