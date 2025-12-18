// api/chat/v1/_lib/redisAdapter.js
import { Redis as UpstashRedis } from '@upstash/redis';

const isDev = process.env.NODE_ENV !== 'production';
let commandFallbackLogged = false;
const restRedis =
  process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN
    ? new UpstashRedis({ url: process.env.UPSTASH_REDIS_REST_URL, token: process.env.UPSTASH_REDIS_REST_TOKEN })
    : null;
const warnedFallbacks = new Set();

function unwrapResult(result, fallback) {
  if (result && typeof result === 'object' && 'result' in result) {
    return result.result ?? fallback;
  }
  return result ?? fallback;
}

function ensureArray(result) {
  const value = unwrapResult(result, []);
  if (Array.isArray(value)) return value;
  if (value === null || value === undefined) return [];
  return [value];
}

function ensureObject(result) {
  const value = unwrapResult(result, {});
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  return {};
}

function ensureNumber(result) {
  const value = unwrapResult(result, 0);
  const num = Number(value);
  return Number.isNaN(num) ? 0 : num;
}

function parseJson(value, fallback = null) {
  if (value === undefined || value === null || value === '') return fallback;
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value) : value;
    if (parsed === undefined || parsed === null) return fallback;
    return parsed;
  } catch {
    return fallback;
  }
}

function logCommandFallback(op) {
  if (commandFallbackLogged || !isDev) return;
  commandFallbackLogged = true;
  console.debug(`[chat/redisAdapter] using command fallback for ${op}`);
}

function logRestFallback(op) {
  if (warnedFallbacks.has(op)) return;
  warnedFallbacks.add(op);
  console.warn(`[redisAdapter] fallback to REST for ${op}`);
}

function hasFn(obj, name) {
  return Boolean(obj && typeof obj[name] === 'function');
}

function parseWithScores(result) {
  const list = ensureArray(result);
  if (list.length === 0) return [];
  if (typeof list[0] === 'object' && list[0] !== null && 'member' in list[0]) return list;
  const parsed = [];
  for (let i = 0; i < list.length; i += 2) {
    const member = list[i];
    const score = Number(list[i + 1]);
    if (member === undefined) continue;
    parsed.push({ member, score });
  }
  return parsed;
}

export function createRedisAdapter(redis) {
  const hasCommand = hasFn(redis, 'command');
  const hasZrange = hasFn(redis, 'zrange');
  const hasZrevrange = hasFn(redis, 'zrevrange');

  const callOrFallback = async (primaryFnName, args, { restCall, commandArgs } = {}) => {
    if (hasFn(redis, primaryFnName)) return redis[primaryFnName](...args);
    if (restRedis && restCall) {
      logRestFallback(primaryFnName.toUpperCase());
      return restCall();
    }
    if (hasCommand && commandArgs) {
      logCommandFallback(commandArgs[0]);
      return redis.command(commandArgs);
    }
    logRestFallback(primaryFnName.toUpperCase());
    return undefined;
  };

  return {
    hasCommand,
    hasZrange,
    hasZrevrange,

    async get(key) {
      const value = await callOrFallback('get', [key], {
        restCall: () => restRedis?.get(key),
        commandArgs: ['GET', key],
      });
      return unwrapResult(value, null);
    },

    async set(key, value, options) {
      return callOrFallback('set', [key, value, options], {
        restCall: () => restRedis?.set(key, value, options),
        commandArgs: ['SET', key, value],
      });
    },

    async getJson(key, fallback = null) {
      return parseJson(await this.get(key), fallback);
    },

    async setJson(key, value, options) {
      const payload = JSON.stringify(value ?? null);
      return this.set(key, payload, options);
    },

    async zrevrange(key, start, stop, withScores = false) {
      if (hasFn(redis, 'zrevrange')) {
        return ensureArray(await redis.zrevrange(key, start, stop, { withScores }));
      }
      if (hasZrange) {
        const raw = await redis.zrange(key, start, stop, { rev: true, withScores });
        return withScores ? parseWithScores(raw) : ensureArray(raw);
      }
      const raw = await callOrFallback('zrevrange', [key, start, stop], {
        restCall: () => restRedis?.zrange(key, start, stop, { rev: true, withScores }),
        commandArgs: ['ZREVRANGE', key, String(start), String(stop)].concat(withScores ? ['WITHSCORES'] : []),
      });
      return withScores ? parseWithScores(raw) : ensureArray(raw);
    },

    async zrange(key, start, stop, options = {}) {
      if (hasZrange) {
        const raw = await redis.zrange(key, start, stop, options);
        return options?.withScores ? parseWithScores(raw) : ensureArray(raw);
      }
      const args = ['ZRANGE', key, String(start), String(stop)];
      if (options?.rev) args.push('REV');
      if (options?.withScores) args.push('WITHSCORES');
      const raw = await callOrFallback('zrange', [key, start, stop, options], {
        restCall: () => restRedis?.zrange(key, start, stop, options),
        commandArgs: args,
      });
      return options?.withScores ? parseWithScores(raw) : ensureArray(raw);
    },

    async zrangebyscore(key, min, max, { limit, offset, rev, withScores } = {}) {
      if (hasFn(redis, 'zrangebyscore')) {
        const raw = await redis.zrangebyscore(key, min, max, { limit, offset, rev, withScores });
        return withScores ? parseWithScores(raw) : ensureArray(raw);
      }
      if (hasZrange) {
        const options = { byScore: true, rev, withScores };
        if (limit !== undefined) {
          options.limit = { offset: Number(offset) || 0, count: Number(limit) || 0 };
        }
        const raw = await redis.zrange(key, min, max, options);
        return withScores ? parseWithScores(raw) : ensureArray(raw);
      }
      const command = [rev ? 'ZREVRANGEBYSCORE' : 'ZRANGEBYSCORE', key, String(rev ? max : min), String(rev ? min : max)];
      if (withScores) command.push('WITHSCORES');
      if (limit !== undefined) {
        command.push('LIMIT', String(Number(offset) || 0), String(Number(limit) || 0));
      }
      const raw = await callOrFallback('zrangebyscore', [key, min, max, { limit, offset, rev, withScores }], {
        restCall: () =>
          restRedis?.zrange(key, min, max, {
            byScore: true,
            rev,
            withScores,
            offset: Number(offset) || 0,
            count: limit !== undefined ? Number(limit) || 0 : undefined,
          }),
        commandArgs: command,
      });
      return withScores ? parseWithScores(raw) : ensureArray(raw);
    },

    async zadd(key, scoreOrEntries, memberMaybe) {
      const entries = [];
      if (Array.isArray(scoreOrEntries)) {
        entries.push(...scoreOrEntries);
      } else if (
        typeof scoreOrEntries === 'object' &&
        scoreOrEntries !== null &&
        memberMaybe === undefined
      ) {
        entries.push(scoreOrEntries);
      } else {
        entries.push({ score: scoreOrEntries, member: memberMaybe });
      }

      if (hasFn(redis, 'zadd')) {
        return redis.zadd(key, ...entries);
      }
      const args = ['ZADD', key];
      for (const entry of entries) {
        args.push(String(entry.score), entry.member);
      }
      return callOrFallback('zadd', [key, entries], {
        restCall: () => restRedis?.zadd(key, ...entries),
        commandArgs: args,
      });
    },

    async zrem(key, members) {
      const list = Array.isArray(members) ? members : [members];
      if (hasFn(redis, 'zrem')) {
        return redis.zrem(key, ...list);
      }
      return callOrFallback('zrem', [key, ...list], {
        restCall: () => restRedis?.zrem(key, ...list),
        commandArgs: ['ZREM', key, ...list],
      });
    },

    async sadd(key, ...members) {
      if (hasFn(redis, 'sadd')) {
        return redis.sadd(key, ...members);
      }
      return callOrFallback('sadd', [key, ...members], {
        restCall: () => restRedis?.sadd(key, ...members),
        commandArgs: ['SADD', key, ...members],
      });
    },

    async smembers(key) {
      let raw;
      if (hasFn(redis, 'smembers')) {
        raw = await redis.smembers(key);
      } else {
        raw = await callOrFallback('smembers', [key], {
          restCall: () => restRedis?.smembers(key),
          commandArgs: ['SMEMBERS', key],
        });
      }
      return ensureArray(raw);
    },

    async sismember(key, member) {
      if (hasFn(redis, 'sismember')) {
        return Boolean(await redis.sismember(key, member));
      }
      const value = await callOrFallback('sismember', [key, member], {
        restCall: () => restRedis?.sismember(key, member),
        commandArgs: ['SISMEMBER', key, member],
      });
      return ensureNumber(value) === 1 || value === true;
    },

    async hset(key, objOrPairs) {
      if (hasFn(redis, 'hset')) {
        return redis.hset(key, objOrPairs);
      }
      const args = ['HSET', key];
      if (Array.isArray(objOrPairs)) {
        args.push(...objOrPairs.flat());
      } else {
        for (const [field, value] of Object.entries(objOrPairs || {})) {
          args.push(field, value);
        }
      }
      return callOrFallback('hset', [key, objOrPairs], {
        restCall: () => restRedis?.hset(key, objOrPairs),
        commandArgs: args,
      });
    },

    async hgetall(key) {
      let raw;
      if (hasFn(redis, 'hgetall')) {
        raw = await redis.hgetall(key);
      } else {
        raw = await callOrFallback('hgetall', [key], {
          restCall: () => restRedis?.hgetall(key),
          commandArgs: ['HGETALL', key],
        });
      }
      if (raw && typeof raw === 'object' && !Array.isArray(raw)) return raw;
      const pairs = ensureArray(raw);
      const obj = {};
      for (let i = 0; i < pairs.length; i += 2) {
        if (pairs[i] === undefined) continue;
        obj[pairs[i]] = pairs[i + 1];
      }
      return obj;
    },

    async del(...keys) {
      if (hasFn(redis, 'del')) {
        return redis.del(...keys);
      }
      return callOrFallback('del', keys, {
        restCall: () => restRedis?.del(...keys),
        commandArgs: ['DEL', ...keys],
      });
    },

    async exists(key) {
      let value;
      if (hasFn(redis, 'exists')) {
        value = await redis.exists(key);
      } else {
        value = await callOrFallback('exists', [key], {
          restCall: () => restRedis?.exists(key),
          commandArgs: ['EXISTS', key],
        });
      }
      return ensureNumber(value);
    },

    async zcard(key) {
      let value;
      if (hasFn(redis, 'zcard')) {
        value = await redis.zcard(key);
      } else {
        value = await callOrFallback('zcard', [key], {
          restCall: () => restRedis?.zcard(key),
          commandArgs: ['ZCARD', key],
        });
      }
      return ensureNumber(value);
    },

    async keys(pattern) {
      let value;
      if (hasFn(redis, 'keys')) {
        value = await redis.keys(pattern);
      } else {
        value = await callOrFallback('keys', [pattern], {
          restCall: () => restRedis?.keys(pattern),
          commandArgs: ['KEYS', pattern],
        });
      }
      return ensureArray(value);
    },

    async scan(cursor, { match, count } = {}) {
      if (hasFn(redis, 'scan')) {
        const raw = await redis.scan(cursor, { match, count });
        if (Array.isArray(raw)) return raw;
        if (raw && typeof raw === 'object') return { cursor: raw.cursor ?? 0, keys: raw.keys ?? [] };
        return { cursor: 0, keys: [] };
      }
      const args = ['SCAN', String(cursor)];
      if (match) args.push('MATCH', match);
      if (count) args.push('COUNT', String(count));
      const raw = await callOrFallback('scan', [cursor, { match, count }], {
        restCall: () => restRedis?.scan(cursor, { match, count }),
        commandArgs: args,
      });
      const parsed = ensureArray(raw);
      const nextCursor = parsed[0] ?? 0;
      const keys = Array.isArray(parsed[1]) ? parsed[1] : [];
      return { cursor: Number(nextCursor), keys };
    },
  };
}
