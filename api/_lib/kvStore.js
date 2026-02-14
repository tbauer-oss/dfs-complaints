import { getDbClient, query } from './db.js';

const TABLE = 'kv_store';

function toStoreError(err) {
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
  return String(pattern || '*').replace(/\*/g, '%');
}

async function readValue(key) {
  const { rows } = await query(
    `SELECT v, expires_at FROM ${TABLE} WHERE k = $1 AND (expires_at IS NULL OR expires_at > NOW())`,
    [key],
  );
  return rows[0]?.v ?? null;
}

async function writeValue(key, value, exSeconds = null) {
  await query(
    `INSERT INTO ${TABLE} (k, v, expires_at)
     VALUES ($1, $2::jsonb, CASE WHEN $3::int IS NULL THEN NULL ELSE NOW() + ($3::text || ' seconds')::interval END)
     ON CONFLICT (k) DO UPDATE
       SET v = EXCLUDED.v,
           expires_at = EXCLUDED.expires_at,
           updated_at = NOW()`,
    [key, JSON.stringify(value ?? null), exSeconds],
  );
}

async function readContainer(key, expectedType, fallback) {
  const value = await readValue(key);
  if (!value || typeof value !== 'object' || value.__type !== expectedType) return fallback;
  return value.value;
}

async function writeContainer(key, type, value) {
  await writeValue(key, { __type: type, value });
}

export function createKvRedisCompat() {
  return {
    async ping() { return 'PONG'; },

    async get(key) {
      try { return await readValue(key); } catch (e) { throw toStoreError(e); }
    },

    async set(key, value, options = {}) {
      try {
        await writeValue(key, value, options?.ex ?? null);
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
        const map = new Map(rows.map((r) => [r.k, r.v]));
        return list.map((k) => map.has(k) ? map.get(k) : null);
      } catch (e) { throw toStoreError(e); }
    },

    async keys(pattern = '*') {
      try {
        const like = globToLike(pattern);
        const { rows } = await query(
          `SELECT k FROM ${TABLE} WHERE k LIKE $1 AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY k`,
          [like],
        );
        return rows.map((r) => r.k);
      } catch (e) { throw toStoreError(e); }
    },

    async scan(cursor = '0', { match = '*', count = 100 } = {}) {
      try {
        const like = globToLike(match);
        const start = cursor === '0' ? '' : String(cursor);
        const { rows } = await query(
          `SELECT k FROM ${TABLE}
            WHERE k LIKE $1
              AND (expires_at IS NULL OR expires_at > NOW())
              AND ($2 = '' OR k > $2)
            ORDER BY k
            LIMIT $3`,
          [like, start, Number(count) || 100],
        );
        const keys = rows.map((r) => r.k);
        const next = keys.length < (Number(count) || 100) ? '0' : keys[keys.length - 1];
        return [next, keys];
      } catch (e) { throw toStoreError(e); }
    },

    async incr(key) {
      let client;
      try {
        client = await getDbClient();
        await client.query('BEGIN');
        const current = await client.query(`SELECT v FROM ${TABLE} WHERE k = $1 FOR UPDATE`, [key]);
        const existing = current.rows[0]?.v;
        const num = typeof existing === 'number' ? existing : Number(existing || 0) || 0;
        const next = num + 1;
        await client.query(
          `INSERT INTO ${TABLE} (k, v, expires_at)
           VALUES ($1, $2::jsonb, NULL)
           ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v, updated_at = NOW()`,
          [key, JSON.stringify(next)],
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
        const res = await query(
          `UPDATE ${TABLE} SET expires_at = NOW() + ($2::text || ' seconds')::interval, updated_at = NOW() WHERE k = $1`,
          [key, Number(seconds) || 0],
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

    async exists(key) {
      return (await this.get(key)) === null ? 0 : 1;
    },

    async sadd(key, ...members) {
      const list = asArray(members).map(String);
      try {
        const set = new Set((await readContainer(key, 'set', [])) || []);
        let added = 0;
        for (const member of list) {
          if (!set.has(member)) { set.add(member); added += 1; }
        }
        await writeContainer(key, 'set', Array.from(set));
        return added;
      } catch (e) { throw toStoreError(e); }
    },

    async smembers(key) {
      try { return (await readContainer(key, 'set', [])) || []; } catch (e) { throw toStoreError(e); }
    },

    async srem(key, ...members) {
      const list = asArray(members).map(String);
      try {
        const set = new Set((await readContainer(key, 'set', [])) || []);
        let removed = 0;
        for (const member of list) {
          if (set.delete(member)) removed += 1;
        }
        await writeContainer(key, 'set', Array.from(set));
        return removed;
      } catch (e) { throw toStoreError(e); }
    },

    async sismember(key, member) {
      const list = await this.smembers(key);
      return list.includes(String(member)) ? 1 : 0;
    },

    async hset(key, objOrPairs) {
      try {
        const current = (await readContainer(key, 'hash', {})) || {};
        if (Array.isArray(objOrPairs)) {
          for (const [field, value] of objOrPairs) current[field] = value;
        } else {
          Object.assign(current, objOrPairs || {});
        }
        await writeContainer(key, 'hash', current);
        return 1;
      } catch (e) { throw toStoreError(e); }
    },

    async hget(key, field) {
      const hash = await this.hgetall(key);
      return Object.prototype.hasOwnProperty.call(hash, field) ? hash[field] : null;
    },

    async hgetall(key) {
      try { return (await readContainer(key, 'hash', {})) || {}; } catch (e) { throw toStoreError(e); }
    },

    async hdel(key, ...fields) {
      try {
        const hash = (await readContainer(key, 'hash', {})) || {};
        let removed = 0;
        for (const field of fields) {
          if (Object.prototype.hasOwnProperty.call(hash, field)) {
            delete hash[field];
            removed += 1;
          }
        }
        await writeContainer(key, 'hash', hash);
        return removed;
      } catch (e) { throw toStoreError(e); }
    },

    async rpush(key, ...values) {
      try {
        const list = (await readContainer(key, 'list', [])) || [];
        list.push(...values);
        await writeContainer(key, 'list', list);
        return list.length;
      } catch (e) { throw toStoreError(e); }
    },

    async lrange(key, start, stop) {
      try {
        const list = (await readContainer(key, 'list', [])) || [];
        const from = Number(start) < 0 ? Math.max(list.length + Number(start), 0) : Number(start);
        const toIdx = Number(stop) < 0 ? list.length + Number(stop) : Number(stop);
        return list.slice(from, toIdx + 1);
      } catch (e) { throw toStoreError(e); }
    },

    async zadd(key, ...entries) {
      try {
        const zset = (await readContainer(key, 'zset', [])) || [];
        const normalized = Array.isArray(entries[0]) ? entries[0] : entries;
        const map = new Map(zset.map((it) => [String(it.member), Number(it.score)]));
        for (const e of normalized) {
          map.set(String(e.member), Number(e.score));
        }
        const next = Array.from(map.entries()).map(([member, score]) => ({ member, score }));
        await writeContainer(key, 'zset', next);
        return normalized.length;
      } catch (e) { throw toStoreError(e); }
    },

    async zrem(key, ...members) {
      try {
        const zset = (await readContainer(key, 'zset', [])) || [];
        const set = new Set(asArray(members).map(String));
        const next = zset.filter((e) => !set.has(String(e.member)));
        await writeContainer(key, 'zset', next);
        return zset.length - next.length;
      } catch (e) { throw toStoreError(e); }
    },

    async zcard(key) {
      const z = (await readContainer(key, 'zset', [])) || [];
      return z.length;
    },

    async zrange(key, start, stop, options = {}) {
      const z = ((await readContainer(key, 'zset', [])) || []).slice().sort((a, b) => a.score - b.score);
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
      const from = Number(start);
      const to = Number(stop);
      const slice = arr.slice(from, to === -1 ? undefined : to + 1);
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
