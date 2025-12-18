// api/chat/v1/_lib/redisAdapter.js
const isDev = process.env.NODE_ENV !== 'production';
let commandFallbackLogged = false;

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
  const hasCommand = typeof redis.command === 'function';
  const hasZrange = typeof redis.zrange === 'function';
  const hasZrevrange = typeof redis.zrevrange === 'function';

  const runCommand = async (args) => {
    logCommandFallback(args[0]);
    return redis.command(args);
  };

  return {
    hasCommand,
    hasZrange,
    hasZrevrange,

    async getJson(key, fallback = null) {
      if (typeof redis.get === 'function') {
        return parseJson(await redis.get(key), fallback);
      }
      if (hasCommand) {
        return parseJson(await runCommand(['GET', key]), fallback);
      }
      throw new Error('Redis client missing GET support');
    },

    async setJson(key, value) {
      const payload = JSON.stringify(value ?? null);
      if (typeof redis.set === 'function') {
        return redis.set(key, payload);
      }
      if (hasCommand) {
        return runCommand(['SET', key, payload]);
      }
      throw new Error('Redis client missing SET support');
    },

    async zrevrange(key, start, stop) {
      if (typeof redis.zrevrange === 'function') {
        return ensureArray(await redis.zrevrange(key, start, stop));
      }
      if (hasZrange) {
        return ensureArray(await redis.zrange(key, start, stop, { rev: true }));
      }
      if (hasCommand) {
        return ensureArray(await runCommand(['ZREVRANGE', key, String(start), String(stop)]));
      }
      throw new Error('Redis client missing ZREVRANGE support');
    },

    async zrange(key, start, stop, options = {}) {
      if (hasZrange) {
        return ensureArray(await redis.zrange(key, start, stop, options));
      }
      if (hasCommand) {
        const args = ['ZRANGE', key, String(start), String(stop)];
        if (options?.rev) args.push('REV');
        if (options?.withScores) args.push('WITHSCORES');
        const raw = await runCommand(args);
        return options?.withScores ? parseWithScores(raw) : ensureArray(raw);
      }
      throw new Error('Redis client missing ZRANGE support');
    },

    async zrangebyscore(key, min, max, { limit, offset, rev } = {}) {
      if (typeof redis.zrangebyscore === 'function') {
        return ensureArray(await redis.zrangebyscore(key, min, max, { limit, offset, rev }));
      }
      if (hasZrange) {
        const options = { byScore: true };
        if (rev) options.rev = true;
        if (limit !== undefined) {
          options.limit = { offset: Number(offset) || 0, count: Number(limit) || 0 };
        }
        return ensureArray(await redis.zrange(key, min, max, options));
      }
      if (hasCommand) {
        const args = [rev ? 'ZREVRANGEBYSCORE' : 'ZRANGEBYSCORE', key, String(rev ? max : min), String(rev ? min : max)];
        if (limit !== undefined) {
          args.push('LIMIT', String(Number(offset) || 0), String(Number(limit) || 0));
        }
        const raw = await runCommand(args);
        return ensureArray(raw);
      }
      throw new Error('Redis client missing ZRANGEBYSCORE support');
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

      if (typeof redis.zadd === 'function') {
        return redis.zadd(key, ...entries);
      }
      if (hasCommand) {
        const args = ['ZADD', key];
        for (const entry of entries) {
          args.push(String(entry.score), entry.member);
        }
        return runCommand(args);
      }
      throw new Error('Redis client missing ZADD support');
    },

    async zrem(key, members) {
      const list = Array.isArray(members) ? members : [members];
      if (typeof redis.zrem === 'function') {
        return redis.zrem(key, ...list);
      }
      if (hasCommand) {
        return runCommand(['ZREM', key, ...list]);
      }
      throw new Error('Redis client missing ZREM support');
    },

    async sadd(key, ...members) {
      if (typeof redis.sadd === 'function') {
        return redis.sadd(key, ...members);
      }
      if (hasCommand) {
        return runCommand(['SADD', key, ...members]);
      }
      throw new Error('Redis client missing SADD support');
    },

    async smembers(key) {
      if (typeof redis.smembers === 'function') {
        return ensureArray(await redis.smembers(key));
      }
      if (hasCommand) {
        return ensureArray(await runCommand(['SMEMBERS', key]));
      }
      throw new Error('Redis client missing SMEMBERS support');
    },

    async sismember(key, member) {
      if (typeof redis.sismember === 'function') {
        return Boolean(await redis.sismember(key, member));
      }
      if (hasCommand) {
        const value = await runCommand(['SISMEMBER', key, member]);
        return ensureNumber(value) === 1;
      }
      throw new Error('Redis client missing SISMEMBER support');
    },

    async hset(key, objOrPairs) {
      if (typeof redis.hset === 'function') {
        return redis.hset(key, objOrPairs);
      }
      if (hasCommand) {
        if (Array.isArray(objOrPairs)) {
          return runCommand(['HSET', key, ...objOrPairs.flat()]);
        }
        const args = ['HSET', key];
        for (const [field, value] of Object.entries(objOrPairs || {})) {
          args.push(field, value);
        }
        return runCommand(args);
      }
      throw new Error('Redis client missing HSET support');
    },

    async hgetall(key) {
      if (typeof redis.hgetall === 'function') {
        return ensureObject(await redis.hgetall(key));
      }
      if (hasCommand) {
        const raw = await runCommand(['HGETALL', key]);
        const pairs = ensureArray(raw);
        const obj = {};
        for (let i = 0; i < pairs.length; i += 2) {
          if (pairs[i] === undefined) continue;
          obj[pairs[i]] = pairs[i + 1];
        }
        return obj;
      }
      throw new Error('Redis client missing HGETALL support');
    },

    async del(...keys) {
      if (typeof redis.del === 'function') {
        return redis.del(...keys);
      }
      if (hasCommand) {
        return runCommand(['DEL', ...keys]);
      }
      throw new Error('Redis client missing DEL support');
    },

    async exists(key) {
      if (typeof redis.exists === 'function') {
        return ensureNumber(await redis.exists(key));
      }
      if (hasCommand) {
        return ensureNumber(await runCommand(['EXISTS', key]));
      }
      throw new Error('Redis client missing EXISTS support');
    },

    async zcard(key) {
      if (typeof redis.zcard === 'function') {
        return ensureNumber(await redis.zcard(key));
      }
      if (hasCommand) {
        return ensureNumber(await runCommand(['ZCARD', key]));
      }
      throw new Error('Redis client missing ZCARD support');
    },

    async keys(pattern) {
      if (typeof redis.keys === 'function') {
        return ensureArray(await redis.keys(pattern));
      }
      if (hasCommand) {
        return ensureArray(await runCommand(['KEYS', pattern]));
      }
      throw new Error('Redis client missing KEYS support');
    },

    async scan(cursor, { match, count } = {}) {
      if (typeof redis.scan === 'function') {
        const raw = await redis.scan(cursor, { match, count });
        if (Array.isArray(raw)) return raw;
        if (raw && typeof raw === 'object') return { cursor: raw.cursor ?? 0, keys: raw.keys ?? [] };
        return { cursor: 0, keys: [] };
      }
      if (hasCommand) {
        const args = ['SCAN', String(cursor)];
        if (match) args.push('MATCH', match);
        if (count) args.push('COUNT', String(count));
        const raw = await runCommand(args);
        const parsed = ensureArray(raw);
        const nextCursor = parsed[0] ?? 0;
        const keys = Array.isArray(parsed[1]) ? parsed[1] : [];
        return { cursor: Number(nextCursor), keys };
      }
      throw new Error('Redis client missing SCAN support');
    },
  };
}
