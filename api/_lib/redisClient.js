import { Redis } from '@upstash/redis';
import { AsyncLocalStorage } from 'node:async_hooks';

const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  process.env.KV_REST_API_URL ||
  process.env.REDIS_URL ||
  null;

const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  process.env.KV_REST_API_TOKEN ||
  process.env.REDIS_TOKEN ||
  null;

export const REDIS_TIMEOUT_MS = Math.max(0, Number(process.env.REDIS_TIMEOUT_MS || 2500));

const redisContext = new AsyncLocalStorage();
let redisInstance = null;
let redisOverride = null;

export function runWithRedisContext(ctx = {}, fn = () => {}) {
  if (typeof fn !== 'function') return fn;
  return redisContext.run({ ...ctx }, fn);
}

export function getRedisContext() {
  return redisContext.getStore() || {};
}

export function __setRedisClientForTests(client = null) {
  redisOverride = client;
  redisInstance = client;
}

export function getRedisInstance() {
  if (redisOverride) return redisOverride;
  if (redisInstance) return redisInstance;
  if (!REDIS_URL || !REDIS_TOKEN) return null;
  redisInstance = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return redisInstance;
}

async function withRedisTimeout(promise, label = 'redis op') {
  if (!REDIS_TIMEOUT_MS) return await promise;
  return await Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => {
        const err = new Error(`${label} timed out after ${REDIS_TIMEOUT_MS}ms`);
        err.code = 'REDIS_TIMEOUT';
        reject(err);
      }, REDIS_TIMEOUT_MS);
    }),
  ]);
}

const READ_ONLY_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

function guardWrite(operation, key) {
  const ctx = getRedisContext();
  const method = (ctx.method || '').toString().toUpperCase();
  if (!method || !READ_ONLY_METHODS.has(method)) return;
  const err = new Error(`Redis write blocked for read-only method ${method}`);
  console.error('[redis-write-guard]', {
    route: ctx.route,
    method,
    auditId: ctx.auditId,
    key,
    stack: (err.stack || '').split('\n').slice(1, 6),
  });
  throw err;
}

function logWrite(operation, key) {
  const ctx = getRedisContext();
  console.warn('[audit-redis-write]', {
    operation,
    key: String(key ?? ''),
    route: ctx.route,
    method: ctx.method,
    auditId: ctx.auditId,
  });
}

async function execRead(method, args, { defaultValue = null } = {}) {
  const client = getRedisInstance();
  if (!client || typeof client[method] !== 'function') return defaultValue;
  return await withRedisTimeout(client[method](...args), `REDIS ${method.toUpperCase()}`);
}

async function execWrite(method, key, args, { defaultValue = null } = {}) {
  const client = getRedisInstance();
  if (!client || typeof client[method] !== 'function') return defaultValue;
  guardWrite(method, key);
  logWrite(method, key);
  return await withRedisTimeout(client[method](...args), `REDIS ${method.toUpperCase()}`);
}

async function execJson(method, key, args, { defaultValue = null } = {}) {
  const client = getRedisInstance();
  if (!client?.json || typeof client.json[method] !== 'function') return defaultValue;
  guardWrite(`json.${method}`, key);
  logWrite(`json.${method}`, key);
  return await withRedisTimeout(client.json[method](...args), `REDIS JSON.${method.toUpperCase()}`);
}

export const redisRead = {
  get: (key) => execRead('get', [key], { defaultValue: null }),
  mget: (...keys) => execRead('mget', keys, { defaultValue: [] }),
  smembers: (key) => execRead('smembers', [key], { defaultValue: [] }),
  scan: (cursor, opts) => execRead('scan', [cursor, opts], { defaultValue: [0, []] }),
  keys: (pattern) => execRead('keys', [pattern], { defaultValue: [] }),
  jsonGet: async (key, path = '$') => {
    const client = getRedisInstance();
    if (!client?.json?.get) return null;
    return await withRedisTimeout(client.json.get(key, path), 'REDIS JSON.GET');
  },
};

export const redisWrite = {
  set: (key, value) => {
    const payload = typeof value === 'string' ? value : JSON.stringify(value);
    return execWrite('set', key, [key, payload], { defaultValue: null });
  },
  del: (key, ...rest) => execWrite('del', key, [key, ...rest], { defaultValue: null }),
  sadd: (key, ...members) => execWrite('sadd', key, [key, ...members], { defaultValue: 0 }),
  srem: (key, ...members) => execWrite('srem', key, [key, ...members], { defaultValue: 0 }),
  hset: (key, value) => execWrite('hset', key, [key, value], { defaultValue: 0 }),
  incr: (key) => execWrite('incr', key, [key], { defaultValue: null }),
  jsonSet: (key, path, value) => execJson('set', key, [key, path, value], { defaultValue: null }),
};

export { withRedisTimeout };
