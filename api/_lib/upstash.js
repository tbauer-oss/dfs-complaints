export const config = { runtime: 'nodejs' };

import { redis } from './redis.js';

export async function redisGet(key) {
  return await redis.get(key);
}

export async function redisMGet(keys = []) {
  return await redis.mget(keys);
}

export async function redisScanAll(match, count = 1000) {
  let cursor = '0';
  const out = [];
  do {
    const [next, keys] = await redis.scan(cursor, { match, count });
    out.push(...(keys || []));
    cursor = next;
  } while (cursor !== '0');
  return out;
}
