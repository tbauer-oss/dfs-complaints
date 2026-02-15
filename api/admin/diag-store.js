export const config = { runtime: 'nodejs' };

import { query } from '../_lib/db.js';
import { withCors } from '../_lib/http.js';
import { redis } from '../_lib/redis.js';

function sanitizeError(err) {
  return {
    message: err?.message || String(err),
    code: err?.code || null,
  };
}

function getDbTarget() {
  const value = String(process.env.DATABASE_URL || '').trim();
  if (!value) return '';
  try {
    const parsed = new URL(value);
    const host = String(parsed.hostname || '').trim();
    const port = String(parsed.port || '5432').trim();
    const database = String(parsed.pathname || '').replace(/^\//, '').trim() || 'postgres';
    return `${host}:${port}/${database}`;
  } catch {
    return '';
  }
}

function isAuthorized(req) {
  const expected = String(process.env.ADMIN_SECRET || '').trim();
  if (!expected) return false;

  const headerSecret = String(req.headers?.['x-admin-secret'] || '').trim();
  if (headerSecret && headerSecret === expected) return true;

  const authorization = String(req.headers?.authorization || '').trim();
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  const bearerSecret = String(match?.[1] || '').trim();
  return Boolean(bearerSecret) && bearerSecret === expected;
}

function json(res, status, payload) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = status;
  res.end(JSON.stringify(payload));
}

export default async function handler(req, res) {
  withCors(req, res);
  if (req.method === 'OPTIONS') return res.status(204).end();

  const response = {
    ok: false,
    env: {
      hasDatabaseUrl: Boolean(String(process.env.DATABASE_URL || '').trim()),
      hasJwtSecret: Boolean(String(process.env.JWT_SECRET || '').trim()),
    },
    dbTarget: getDbTarget(),
    db: {
      ping: {
        ok: false,
        ms: null,
      },
    },
    schema: {
      kv_store: null,
      portal_users: null,
    },
    kv: {
      setGetDel: {
        ok: false,
        key: null,
        got: null,
        ms: null,
      },
    },
  };

  try {
    if (req.method !== 'GET') {
      return json(res, 405, { ok: false, code: 'METHOD_NOT_ALLOWED' });
    }

    if (!isAuthorized(req)) {
      return json(res, 401, { ok: false, code: 'UNAUTHORIZED' });
    }

    const dbPingStarted = Date.now();
    try {
      await query('select 1 as ok');
      response.db.ping.ok = true;
    } catch (err) {
      response.db.ping.error = sanitizeError(err);
    } finally {
      response.db.ping.ms = Date.now() - dbPingStarted;
    }

    try {
      const { rows } = await query(
        "select to_regclass('public.kv_store') as kv_store, to_regclass('public.portal_users') as portal_users",
      );
      response.schema.kv_store = rows?.[0]?.kv_store || null;
      response.schema.portal_users = rows?.[0]?.portal_users || null;
    } catch (err) {
      response.schema.error = sanitizeError(err);
    }

    const key = `dfs:diag:ping:${Date.now()}`;
    const kvStarted = Date.now();
    response.kv.setGetDel.key = key;
    try {
      await redis.set(key, { ok: true }, { ex: 60 });
      const got = await redis.get(key);
      await redis.del(key);
      response.kv.setGetDel.ok = true;
      response.kv.setGetDel.got = got ?? null;
    } catch (err) {
      response.kv.setGetDel.error = sanitizeError(err);
    } finally {
      response.kv.setGetDel.ms = Date.now() - kvStarted;
    }

    response.ok = Boolean(
      response.db.ping.ok
      && response.schema.kv_store
      && response.schema.portal_users
      && response.kv.setGetDel.ok,
    );

    return json(res, 200, response);
  } catch (err) {
    return json(res, 200, {
      ...response,
      ok: false,
      fatal: sanitizeError(err),
    });
  }
}
