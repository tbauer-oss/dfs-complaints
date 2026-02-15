#!/usr/bin/env node
import { redis } from '../api/_lib/redis.js';

const UPSTASH_URL = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const UPSTASH_TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();
const START_CURSOR = String(process.env.START_CURSOR || '0').trim() || '0';

const SCAN_COUNT = 1000;
const PIPELINE_BATCH_SIZE = 100;
const PROGRESS_LOG_EVERY = 1000;

if (!UPSTASH_URL || !UPSTASH_TOKEN) {
  console.error('[migrate_all_upstash_to_supabase] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}
if (!process.env.DATABASE_URL) {
  console.error('[migrate_all_upstash_to_supabase] missing DATABASE_URL');
  process.exit(1);
}

function isRateLimitError(status, message) {
  const text = String(message || '').toLowerCase();
  return status === 429 || text.includes('rate limit') || text.includes('too many requests') || text.includes('limit exceeded');
}

function parseValue(value) {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

async function upstashScan(cursor) {
  const url = `${UPSTASH_URL}/scan/${encodeURIComponent(cursor)}?match=${encodeURIComponent('*')}&count=${encodeURIComponent(String(SCAN_COUNT))}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` },
  });

  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }

  if (!res.ok || body?.error) {
    const errorMessage = body?.error || `scan failed (${res.status})`;
    const err = new Error(errorMessage);
    err.status = res.status;
    throw err;
  }

  return body.result;
}

async function upstashPipelineGet(keys) {
  const commands = keys.map((key) => ['GET', key]);
  const res = await fetch(`${UPSTASH_URL}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${UPSTASH_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(commands),
  });

  let body = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }

  if (!res.ok || body?.error) {
    const errorMessage = body?.error || `pipeline failed (${res.status})`;
    const err = new Error(errorMessage);
    err.status = res.status;
    throw err;
  }

  return Array.isArray(body.result) ? body.result : [];
}

async function main() {
  let cursor = START_CURSOR;
  let scanned = 0;
  let written = 0;

  console.log(`[migrate_all_upstash_to_supabase] start cursor=${cursor}`);

  try {
    do {
      const scanResult = await upstashScan(cursor);
      const nextCursor = String(scanResult?.[0] ?? '0');
      const keys = Array.isArray(scanResult?.[1]) ? scanResult[1] : [];

      scanned += keys.length;

      for (let i = 0; i < keys.length; i += PIPELINE_BATCH_SIZE) {
        const batchKeys = keys.slice(i, i + PIPELINE_BATCH_SIZE);
        const responses = await upstashPipelineGet(batchKeys);

        for (let j = 0; j < batchKeys.length; j += 1) {
          const key = batchKeys[j];
          const item = responses[j];

          if (!item || item.error) {
            const err = new Error(item?.error || 'pipeline item missing');
            err.status = 500;
            throw err;
          }

          const parsedValue = parseValue(item.result);
          await redis.set(key, parsedValue);
          written += 1;

          if (written % PROGRESS_LOG_EVERY === 0) {
            console.log(`[migrate_all_upstash_to_supabase] progress scanned=${scanned} written=${written} cursor=${nextCursor}`);
          }
        }
      }

      cursor = nextCursor;
    } while (cursor !== '0');

    console.log(`[migrate_all_upstash_to_supabase] completed scanned=${scanned} written=${written}`);
  } catch (error) {
    const status = Number(error?.status || 0);
    const message = String(error?.message || error);

    if (isRateLimitError(status, message)) {
      console.error(`[migrate_all_upstash_to_supabase] aborted on Upstash limit error. last_cursor=${cursor}. details=${message}`);
      process.exit(2);
    }

    console.error(`[migrate_all_upstash_to_supabase] failed last_cursor=${cursor}. details=${message}`);
    process.exit(1);
  }
}

main();
