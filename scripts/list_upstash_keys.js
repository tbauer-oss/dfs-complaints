#!/usr/bin/env node

const UPSTASH_URL = String(process.env.UPSTASH_REDIS_REST_URL || '').replace(/\/$/, '');
const UPSTASH_TOKEN = String(process.env.UPSTASH_REDIS_REST_TOKEN || '').trim();
const SCAN_COUNT = Math.max(1, Number(process.env.UPSTASH_SCAN_COUNT || 1000));

if (!UPSTASH_URL || !UPSTASH_TOKEN) {
  console.error('[list_upstash_keys] missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
  process.exit(1);
}

function detectPrefix(key) {
  const known = [
    'dfs:portal:user:',
    'dfs:user:',
    'dfs:reps:',
    'dfs:wiki:',
    'dfs:td:',
    'dfs:training:',
    'dfs:chat:',
  ];
  for (const prefix of known) {
    if (key.startsWith(prefix)) return prefix;
  }
  const parts = String(key).split(':');
  if (parts.length >= 3) return `${parts[0]}:${parts[1]}:${parts[2]}:`;
  if (parts.length >= 2) return `${parts[0]}:${parts[1]}:`;
  return `${parts[0]}:`;
}

async function upstashScan(cursor) {
  const url = `${UPSTASH_URL}/scan/${encodeURIComponent(cursor)}?match=${encodeURIComponent('dfs:*')}&count=${encodeURIComponent(String(SCAN_COUNT))}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${UPSTASH_TOKEN}` } });
  if (!res.ok) throw new Error(`scan failed (${res.status})`);
  const body = await res.json();
  if (body?.error) throw new Error(body.error);
  return body?.result;
}

async function main() {
  const counts = new Map();
  let total = 0;
  let cursor = '0';
  let iterations = 0;

  do {
    const result = await upstashScan(cursor);
    cursor = String(result?.[0] ?? '0');
    const keys = Array.isArray(result?.[1]) ? result[1] : [];
    total += keys.length;
    iterations += 1;

    for (const key of keys) {
      const prefix = detectPrefix(key);
      counts.set(prefix, (counts.get(prefix) || 0) + 1);
    }

    if (iterations % 10 === 0) {
      console.log(`[list_upstash_keys] scanned=${total} cursor=${cursor}`);
    }
  } while (cursor !== '0');

  const sorted = Array.from(counts.entries()).sort((a, b) => b[1] - a[1]);
  console.log(`\n[list_upstash_keys] total dfs:* keys = ${total}`);
  console.log('[list_upstash_keys] counts by prefix:');
  for (const [prefix, count] of sorted) {
    console.log(`  ${prefix.padEnd(24)} ${count}`);
  }
}

main().catch((err) => {
  console.error('[list_upstash_keys] failed', err.message);
  process.exit(1);
});

