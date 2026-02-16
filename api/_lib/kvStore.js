import { getDbClient, query } from './db.js';

const TABLE = 'kv_store';

function toStoreError(err) {
  if (String(err?.code || '') === 'SECURITY_GUARD_AUTH_CACHE_FORBIDDEN' || String(err?.message || '') === 'SECURITY_GUARD_AUTH_CACHE_FORBIDDEN') {
    throw err;
  }
  const error = new Error('STORE_UNAVAILABLE');
  error.code = 'STORE_UNAVAILABLE';
  error.status = 503;
  error.cause = err;
  return error;
}

function asArray(args) {
  if (args.length === 1 && Array.isArray(args[0])) return args[0];
  return args;
}

function globToLike(pattern = '*') {
  return String(pattern || '*')
    .replace(/[\\%_]/g, (m) => `\\${m}`)
    .replace(/\*/g, '%');
}

function canonicalize(type, value) {
  if (type === 'string') return { __type: 'string', value: value ?? null };
  if (type === 'set') return { __type: 'set', members: Array.isArray(value) ? value : [] };
  if (type === 'hash') return { __type: 'hash', value: value && typeof value === 'object' ? value : {} };
  if (type === 'list') return { __type: 'list', items: Array.isArray(value) ? value : [] };
  if (type === 'zset') return { __type: 'zset', items: Array.isArray(value) ? value : [] };
  return { __type: 'string', value: value ?? null };
}

function decodeStored(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return raw ?? null;
  if (raw.__type === 'string') return raw.value ?? null;
  if (raw.__type === 'set') return Array.isArray(raw.members) ? raw.members : (Array.isArray(raw.value) ? raw.value : []);
  if (raw.__type === 'hash') return raw.value && typeof raw.value === 'object' ? raw.value : {};
  if (raw.__type === 'list') return Array.isArray(raw.items) ? raw.items : (Array.isArray(raw.value) ? raw.value : []);
  if (raw.__type === 'zset') return Array.isArray(raw.items) ? raw.items : (Array.isArray(raw.value) ? raw.value : []);
  return raw;
}

async function readRaw(key) {
  const { rows } = await query(
    `SELECT v, expires_at FROM ${TABLE} WHERE k = $1 AND (expires_at IS NULL OR expires_at > NOW())`,
    [key],
  );
  return rows[0]?.v ?? null;
}

async function readValue(key) {
  return decodeStored(await readRaw(key));
}

async function writeRaw(key, rawValue, exSeconds = null) {
  await query(
    `INSERT INTO ${TABLE} (k, v, expires_at)
     VALUES ($1, $2::jsonb, CASE WHEN $3::int IS NULL THEN NULL ELSE NOW() + ($3::text || ' seconds')::interval END)
     ON CONFLICT (k) DO UPDATE
       SET v = EXCLUDED.v,
           expires_at = EXCLUDED.expires_at,
           updated_at = NOW()`,
    [key, JSON.stringify(rawValue ?? null), exSeconds],
  );
}

async function readTyped(key, expectedType, fallback) {
  const raw = await readRaw(key);
  if (!raw || typeof raw !== 'object' || raw.__type !== expectedType) return fallback;
  if (expectedType === 'set') return Array.isArray(raw.members) ? raw.members : (Array.isArray(raw.value) ? raw.value : []);
  if (expectedType === 'hash') return raw.value && typeof raw.value === 'object' ? raw.value : {};
  if (expectedType === 'list') return Array.isArray(raw.items) ? raw.items : (Array.isArray(raw.value) ? raw.value : []);
  if (expectedType === 'zset') return Array.isArray(raw.items) ? raw.items : (Array.isArray(raw.value) ? raw.value : []);
  return fallback;
}

async function writeTyped(key, type, value, exSeconds = null) {
  await writeRaw(key, canonicalize(type, value), exSeconds);
}


function throwAuthCacheForbidden() {
  const err = new Error('SECURITY_GUARD_AUTH_CACHE_FORBIDDEN');
  err.code = 'SECURITY_GUARD_AUTH_CACHE_FORBIDDEN';
  console.warn('[kvStore] ignoring forbidden auth-cache access');
  return err;
}

function isPortalLegacyAuthKey(key) {
  const normalized = String(key || '').trim().toLowerCase();
  return normalized.startsWith('dfs:portal:user:') || normalized.startsWith('dfs:portal:user_safe:');
}

function hasPasswordHashField(value) {
  if (!value || typeof value !== 'object') return false;
  if (Array.isArray(value)) return value.some((entry) => hasPasswordHashField(entry));
  if (Object.prototype.hasOwnProperty.call(value, 'password_hash')) return true;
  if (Object.prototype.hasOwnProperty.call(value, 'passwordHash')) return true;
  if (Object.prototype.hasOwnProperty.call(value, 'passhash')) return true;
  return false;
}

function assertAuthCacheReadAllowed({ key, field = null, value = undefined }) {
  const normalizedField = String(field || '').trim().toLowerCase();
  if (normalizedField === 'password_hash' || normalizedField === 'passwordhash' || normalizedField === 'passhash') {
    throwAuthCacheForbidden();
    return false;
  }
  if (isPortalLegacyAuthKey(key)) {
    throwAuthCacheForbidden();
    return false;
  }
  if (value !== undefined && hasPasswordHashField(value)) {
    throwAuthCacheForbidden();
    return false;
  }
  return true;
}
function normalizeRange(length, start, stop) {
  let from = Number(start);
  let to = Number(stop);
  if (Number.isNaN(from)) from = 0;
  if (Number.isNaN(to)) to = length - 1;

  if (from < 0) from = length + from;
  if (to < 0) to = length + to;

  from = Math.max(from, 0);
  to = Math.min(to, length - 1);

  if (to < from || length <= 0) return [0, -1];
  return [from, to];
}

export function createKvRedisCompat() {
  return {
    async ping() { return 'PONG'; },

    async get(key) {
      try {
        const value = await readValue(key);
        if (!assertAuthCacheReadAllowed({ key, value })) return null;
        return value;
      } catch (e) { throw toStoreError(e); }
    },

    async set(key, value, options = {}) {
      try {
        await writeTyped(key, 'string', value, options?.ex ?? null);
        return 'OK';
      } catch (e) { throw toStoreError(e); }
    },

    async del(...keys) {
      try {
        const list = asArray(keys).filter(Boolean);
        if (!list.length) return 0;
        const res = await query(`DELETE FROM ${TABLE} WHERE k = ANY($1::text[])`, [list]);
        return res.rowCount || 0;
      } catch (e) { throw toStoreError(e); }
    },

    async mget(...keys) {
      try {
        const list = asArray(keys).filter(Boolean);
        if (!list.length) return [];
        const { rows } = await query(
          `SELECT k, v FROM ${TABLE}
           WHERE k = ANY($1::text[]) AND (expires_at IS NULL OR expires_at > NOW())`,
          [list],
        );
        const map = new Map(rows.map((r) => [r.k, decodeStored(r.v)]));
        return list.map((k) => {
          const value = map.has(k) ? map.get(k) : null;
          if (!assertAuthCacheReadAllowed({ key: k, value })) return null;
          return value;
        });
      } catch (e) { throw toStoreError(e); }
    },

    async keys(pattern = '*') {
      try {
        const like = globToLike(pattern);
        const { rows } = await query(
          `SELECT k FROM ${TABLE} WHERE k LIKE $1 ESCAPE '\\' AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY k`,
          [like],
        );
        return rows.map((r) => r.k);
      } catch (e) { throw toStoreError(e); }
    },

    async scan(cursor = '0', { match = '*', count = 100 } = {}) {
      try {
        const limit = Math.max(1, Number(count) || 100);
        const like = globToLike(match);
        const start = cursor === '0' ? '' : String(cursor);
        const { rows } = await query(
          `SELECT k FROM ${TABLE}
            WHERE k LIKE $1 ESCAPE '\\'
              AND (expires_at IS NULL OR expires_at > NOW())
              AND ($2 = '' OR k > $2)
            ORDER BY k
            LIMIT $3`,
          [like, start, limit],
        );
        const keys = rows.map((r) => r.k);
        const next = keys.length < limit ? '0' : keys[keys.length - 1];
        return [next, keys];
      } catch (e) { throw toStoreError(e); }
    },

    async incr(key) {
      let client;
      try {
        client = await getDbClient();
        await client.query('BEGIN');
        const current = await client.query(
          `SELECT v FROM ${TABLE} WHERE k = $1 AND (expires_at IS NULL OR expires_at > NOW()) FOR UPDATE`,
          [key],
        );
        const next = (Number(decodeStored(current.rows[0]?.v) || 0) || 0) + 1;
        await client.query(
          `INSERT INTO ${TABLE} (k, v, expires_at)
           VALUES ($1, $2::jsonb, NULL)
           ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v, expires_at = NULL, updated_at = NOW()`,
          [key, JSON.stringify(canonicalize('string', next))],
        );
        await client.query('COMMIT');
        return next;
      } catch (e) {
        if (client) await client.query('ROLLBACK');
        throw toStoreError(e);
      } finally {
        client?.release();
      }
    },

    async expire(key, seconds) {
      try {
        const sec = Math.max(0, Number(seconds) || 0);
        const res = await query(
          `UPDATE ${TABLE}
           SET expires_at = NOW() + ($2::text || ' seconds')::interval, updated_at = NOW()
           WHERE k = $1 AND (expires_at IS NULL OR expires_at > NOW())`,
          [key, sec],
        );
        return res.rowCount ? 1 : 0;
      } catch (e) { throw toStoreError(e); }
    },

    async ttl(key) {
      try {
        const { rows } = await query(`SELECT expires_at FROM ${TABLE} WHERE k = $1`, [key]);
        if (!rows.length) return -2;
        if (!rows[0].expires_at) return -1;
        const diff = Math.floor((new Date(rows[0].expires_at).getTime() - Date.now()) / 1000);
        return diff < 0 ? -2 : diff;
      } catch (e) { throw toStoreError(e); }
    },

    async exists(...keys) {
      try {
        const list = asArray(keys).filter(Boolean);
        if (!list.length) return 0;
        const { rows } = await query(
          `SELECT COUNT(*)::int AS cnt FROM ${TABLE}
           WHERE k = ANY($1::text[]) AND (expires_at IS NULL OR expires_at > NOW())`,
          [list],
        );
        return rows[0]?.cnt || 0;
      } catch (e) { throw toStoreError(e); }
    },

    async sadd(key, ...members) {
      const list = asArray(members).map(String);
      try {
        const set = new Set((await readTyped(key, 'set', [])) || []);
        let added = 0;
        for (const member of list) {
          if (!set.has(member)) { set.add(member); added += 1; }
        }
        await writeTyped(key, 'set', Array.from(set));
        return added;
      } catch (e) { throw toStoreError(e); }
    },

    async smembers(key) {
      try { return (await readTyped(key, 'set', [])) || []; } catch (e) { throw toStoreError(e); }
    },

    async srem(key, ...members) {
      const list = asArray(members).map(String);
      try {
        const set = new Set((await readTyped(key, 'set', [])) || []);
        let removed = 0;
        for (const member of list) {
          if (set.delete(member)) removed += 1;
        }
        await writeTyped(key, 'set', Array.from(set));
        return removed;
      } catch (e) { throw toStoreError(e); }
    },

    async sismember(key, member) {
      const list = await this.smembers(key);
      return list.includes(String(member)) ? 1 : 0;
    },

    async hset(key, objOrPairs) {
      try {
        const current = { ...((await readTyped(key, 'hash', {})) || {}) };
        if (Array.isArray(objOrPairs)) {
          for (const [field, value] of objOrPairs) current[field] = value;
        } else {
          Object.assign(current, objOrPairs || {});
        }
        await writeTyped(key, 'hash', current);
        return 1;
      } catch (e) { throw toStoreError(e); }
    },

    async hget(key, field) {
      if (!assertAuthCacheReadAllowed({ key, field })) return null;
      const hash = await this.hgetall(key);
      const value = Object.prototype.hasOwnProperty.call(hash, field) ? hash[field] : null;
      if (!assertAuthCacheReadAllowed({ key, field, value })) return null;
      return value;
    },

    async hgetall(key) {
      try {
        const value = (await readTyped(key, 'hash', {})) || {};
        if (!assertAuthCacheReadAllowed({ key, value })) return null;
        return value;
      } catch (e) { throw toStoreError(e); }
    },

    async hdel(key, ...fields) {
      try {
        const hash = { ...((await readTyped(key, 'hash', {})) || {}) };
        let removed = 0;
        for (const field of fields) {
          if (Object.prototype.hasOwnProperty.call(hash, field)) {
            delete hash[field];
            removed += 1;
          }
        }
        await writeTyped(key, 'hash', hash);
        return removed;
      } catch (e) { throw toStoreError(e); }
    },

    async rpush(key, ...values) {
      try {
        const list = (await readTyped(key, 'list', [])) || [];
        list.push(...values);
        await writeTyped(key, 'list', list);
        return list.length;
      } catch (e) { throw toStoreError(e); }
    },

    async lrange(key, start, stop) {
      try {
        const list = (await readTyped(key, 'list', [])) || [];
        const [from, to] = normalizeRange(list.length, start, stop);
        if (to < from) return [];
        return list.slice(from, to + 1);
      } catch (e) { throw toStoreError(e); }
    },

    async zadd(key, ...entries) {
      try {
        const zset = (await readTyped(key, 'zset', [])) || [];
        const normalized = Array.isArray(entries[0]) ? entries[0] : entries;
        const map = new Map(zset.map((it) => [String(it.member), Number(it.score)]));
        for (const e of normalized) {
          map.set(String(e.member), Number(e.score));
        }
        const next = Array.from(map.entries()).map(([member, score]) => ({ member, score }));
        await writeTyped(key, 'zset', next);
        return normalized.length;
      } catch (e) { throw toStoreError(e); }
    },

    async zrem(key, ...members) {
      try {
        const zset = (await readTyped(key, 'zset', [])) || [];
        const set = new Set(asArray(members).map(String));
        const next = zset.filter((e) => !set.has(String(e.member)));
        await writeTyped(key, 'zset', next);
        return zset.length - next.length;
      } catch (e) { throw toStoreError(e); }
    },

    async zcard(key) {
      try {
        const z = (await readTyped(key, 'zset', [])) || [];
        return z.length;
      } catch (e) { throw toStoreError(e); }
    },

    async zrange(key, start, stop, options = {}) {
      const z = ((await readTyped(key, 'zset', [])) || []).slice().sort((a, b) => a.score - b.score);
      const arr = options.rev ? z.reverse() : z;
      if (options.byScore) {
        const min = Number(start);
        const max = Number(stop);
        let filtered = arr.filter((e) => e.score >= Math.min(min, max) && e.score <= Math.max(min, max));
        if (options.limit) {
          const o = Number(options.limit.offset) || 0;
          const c = Number(options.limit.count) || filtered.length;
          filtered = filtered.slice(o, o + c);
        }
        return options.withScores ? filtered : filtered.map((e) => e.member);
      }
      const [from, to] = normalizeRange(arr.length, start, stop);
      if (to < from) return [];
      const slice = arr.slice(from, to + 1);
      return options.withScores ? slice : slice.map((e) => e.member);
    },

    async zrevrange(key, start, stop, { withScores = false } = {}) {
      return this.zrange(key, start, stop, { rev: true, withScores });
    },

    async zrangebyscore(key, min, max, opts = {}) {
      return this.zrange(key, min, max, { ...opts, byScore: true });
    },

    pipeline() {
      const ops = [];
      const api = {
        exec: async () => {
          const out = [];
          for (const [method, args] of ops) {
            out.push(await this[method](...args));
          }
          return out;
        },
      };
      for (const method of ['set', 'get', 'del', 'hset', 'hdel', 'sadd', 'srem', 'rpush', 'expire']) {
        api[method] = (...args) => { ops.push([method, args]); return api; };
      }
      return api;
    },
  };
}
