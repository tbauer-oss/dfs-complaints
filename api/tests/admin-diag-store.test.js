import test from 'node:test';
import assert from 'node:assert/strict';

import diagStoreHandler from '../admin/diag-store.js';
import { __setDbForTests } from '../_lib/db.js';
import { redis } from '../_lib/redis.js';

function makeReq({ method = 'GET', headers = {} } = {}) {
  return {
    method,
    headers: {
      origin: 'https://dfs-complaints-web.vercel.app',
      ...headers,
    },
  };
}

function makeRes() {
  const out = { statusCode: 200, headers: {}, body: '' };
  const res = {
    status(code) { out.statusCode = code; return this; },
    json(payload) { out.body = JSON.stringify(payload ?? {}); return this; },
    setHeader(key, value) { out.headers[String(key).toLowerCase()] = value; },
    getHeader(key) { return out.headers[String(key).toLowerCase()]; },
    end(payload = '') { out.body = payload; return this; },
    __out: out,
  };
  Object.defineProperty(res, 'statusCode', {
    get() { return out.statusCode; },
    set(value) { out.statusCode = Number(value) || out.statusCode; },
  });
  return res;
}

test.afterEach(() => {
  __setDbForTests(null);
});

test('diag-store returns 401 for missing/invalid ADMIN_SECRET', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'top-secret';

  try {
    const req = makeReq();
    const res = makeRes();
    await diagStoreHandler(req, res);

    assert.equal(res.__out.statusCode, 401);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.ok, false);
    assert.equal(payload.code, 'UNAUTHORIZED');
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
  }
});

test('diag-store reports detailed diagnostics and supports Bearer auth', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  const previousDbUrl = process.env.DATABASE_URL;
  const previousJwt = process.env.JWT_SECRET;
  process.env.ADMIN_SECRET = 'top-secret';
  process.env.DATABASE_URL = 'postgresql://user:pass@db.abcd.supabase.co:5432/postgres';
  process.env.JWT_SECRET = 'jwt-secret';

  const originalSet = redis.set;
  const originalGet = redis.get;
  const originalDel = redis.del;

  redis.set = async () => 'OK';
  redis.get = async () => ({ ok: true });
  redis.del = async () => 1;

  let portalLookupHit = false;
  __setDbForTests({
    async query(sql) {
      const normalized = String(sql).toLowerCase();
      if (normalized.includes('select 1 as ok')) return { rows: [{ ok: 1 }] };
      if (normalized.includes("to_regclass('public.kv_store')")) return { rows: [{ exists: 'kv_store' }] };
      if (normalized.includes("to_regclass('public.portal_users')")) return { rows: [{ exists: 'portal_users' }] };
      if (normalized.includes('select email_norm, is_active from portal_users limit 1')) {
        portalLookupHit = true;
        return { rows: [{ email_norm: 'test@example.com', is_active: true }] };
      }
      throw new Error(`unexpected SQL: ${sql}`);
    },
  });

  try {
    const req = makeReq({ headers: { authorization: 'Bearer top-secret' } });
    const res = makeRes();
    await diagStoreHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.ok, true);
    assert.equal(payload.env.hasDatabaseUrl, true);
    assert.equal(payload.env.hasJwtSecret, true);
    assert.equal(payload.db.ok, true);
    assert.equal(payload.db.target, 'db.abcd.supabase.co:5432/postgres');
    assert.equal(payload.schema.kv_store.ok, true);
    assert.equal(payload.schema.portal_users.ok, true);
    assert.equal(payload.kv.setGetDel.ok, true);
    assert.equal(payload.portal.lookup.ok, true);
    assert.equal(payload.portal.lookup.found, true);
    assert.equal(portalLookupHit, true);
  } finally {
    redis.set = originalSet;
    redis.get = originalGet;
    redis.del = originalDel;
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
    if (previousDbUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousDbUrl;
    if (previousJwt === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = previousJwt;
  }
});
