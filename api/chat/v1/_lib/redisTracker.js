// api/chat/v1/_lib/redisTracker.js
import { redis as baseRedis } from '../../../_lib/redis.js';

const READ_OPS = new Set([
  'exists',
  'get',
  'hget',
  'hgetall',
  'hmget',
  'lrange',
  'mget',
  'scan',
  'sismember',
  'smembers',
  'zcard',
  'zrange',
  'zrangebyscore',
  'zrevrange',
  'zrevrangebyscore',
]);

const WRITE_OPS = new Set([
  'del',
  'expire',
  'hdel',
  'hset',
  'incr',
  'sadd',
  'srem',
  'set',
  'zadd',
  'zincrby',
  'zrem',
  'zremrangebyscore',
]);

export function createTrackedRedis(customClient = baseRedis) {
  const counters = { reads: 0, writes: 0 };

  const client = new Proxy(customClient, {
    get(target, prop) {
      const original = target[prop];
      if (typeof original !== 'function') return original;
      return (...args) => {
        const name = prop.toString().toLowerCase();
        if (READ_OPS.has(name)) counters.reads += 1;
        else if (WRITE_OPS.has(name)) counters.writes += 1;
        return original.apply(target, args);
      };
    },
  });

  return { client, counters };
}

export function logRedisUsage(label, counters, extra = {}) {
  const reads = counters.reads || 0;
  const writes = counters.writes || 0;
  console.info(label, { reads, writes, ...extra });
}
