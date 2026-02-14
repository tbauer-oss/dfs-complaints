#!/usr/bin/env node
import { redis } from '../api/_lib/redis.js';

async function main() {
  if (!process.env.DATABASE_URL) {
    console.log('[test_kv_store_basic] skipped (DATABASE_URL not set)');
    process.exit(0);
  }

  const base = `dfs:test:kv:${Date.now()}`;
  await redis.set(`${base}:a`, { x: 1 });
  const got = await redis.get(`${base}:a`);
  if (!got || got.x !== 1) throw new Error('get/set failed');

  await redis.set(`${base}:b`, 'b');
  const arr = await redis.mget([`${base}:a`, `${base}:b`, `${base}:c`]);
  if (!Array.isArray(arr) || arr.length !== 3) throw new Error('mget failed');

  const [cursor, keys] = await redis.scan('0', { match: `${base}:*`, count: 10 });
  if (!Array.isArray(keys) || keys.length < 2) throw new Error('scan failed');
  if (typeof cursor !== 'string') throw new Error('scan cursor failed');

  await redis.del(`${base}:a`, `${base}:b`);
  const gone = await redis.get(`${base}:a`);
  if (gone !== null) throw new Error('del failed');

  console.log('[test_kv_store_basic] ok');
}

main().catch((err) => {
  console.error('[test_kv_store_basic] failed', err.message);
  process.exit(1);
});
