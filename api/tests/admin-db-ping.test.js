import test from 'node:test';
import assert from 'node:assert/strict';

import dbPingHandler from '../admin/db-ping.js';
import { __setDbForTests, getSanitizedDbTarget } from '../_lib/db.js';

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
    setHeader(k, v) { out.headers[String(k).toLowerCase()] = v; },
    getHeader(k) { return out.headers[String(k).toLowerCase()]; },
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

test('admin db-ping returns 401 when admin secret is missing or invalid', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'top-secret';

  try {
    const req = makeReq();
    const res = makeRes();
    await dbPingHandler(req, res);

    assert.equal(res.__out.statusCode, 401);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.code, 'UNAUTHORIZED');
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
  }
});

test('admin db-ping returns ok payload when db query succeeds', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  const previousUrl = process.env.DATABASE_URL;
  process.env.ADMIN_SECRET = 'top-secret';
  process.env.DATABASE_URL = 'postgresql://user:pass@db.abcd.supabase.co:5432/postgres';

  __setDbForTests({
    async query(sql) {
      assert.equal(String(sql).toLowerCase(), 'select 1 as ok');
      return { rows: [{ '?column?': 1 }] };
    },
  });

  try {
    const req = makeReq({ headers: { 'x-admin-secret': 'top-secret' } });
    const res = makeRes();
    await dbPingHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.ok, true);
    assert.equal(payload.target, 'db.abcd.supabase.co:5432/postgres');
    assert.equal(typeof payload.ms, 'number');
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
    if (previousUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousUrl;
  }
});

test('admin db-ping returns DB_UNAVAILABLE payload on query failure', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  const previousUrl = process.env.DATABASE_URL;
  process.env.ADMIN_SECRET = 'top-secret';
  process.env.DATABASE_URL = 'postgresql://user:pass@aws-0-eu.pooler.supabase.com:6543/postgres';

  __setDbForTests({
    async query() {
      const err = new Error('connect failed');
      err.code = 'DB_UNAVAILABLE';
      throw err;
    },
  });

  try {
    const req = makeReq({ headers: { 'x-admin-secret': 'top-secret' } });
    const res = makeRes();
    await dbPingHandler(req, res);

    assert.equal(res.__out.statusCode, 503);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.ok, false);
    assert.equal(payload.code, 'DB_UNAVAILABLE');
    assert.equal(payload.target, 'aws-0-eu.pooler.supabase.com:6543/postgres');
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
    if (previousUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousUrl;
  }
});


test('admin db-ping uses POSTGRES_URL when DATABASE_URL is missing', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  const previousUrl = process.env.DATABASE_URL;
  const previousPostgresUrl = process.env.POSTGRES_URL;
  process.env.ADMIN_SECRET = 'top-secret';
  delete process.env.DATABASE_URL;
  process.env.POSTGRES_URL = 'postgresql://user:pass@fallback-db.internal:6543/postgres';

  __setDbForTests({
    async query(sql) {
      assert.equal(String(sql).toLowerCase(), 'select 1 as ok');
      return { rows: [{ '?column?': 1 }] };
    },
  });

  try {
    const req = makeReq({ headers: { 'x-admin-secret': 'top-secret' } });
    const res = makeRes();
    await dbPingHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.ok, true);
    assert.equal(payload.target, 'fallback-db.internal:6543/postgres');
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
    if (previousUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousUrl;
    if (previousPostgresUrl === undefined) delete process.env.POSTGRES_URL;
    else process.env.POSTGRES_URL = previousPostgresUrl;
  }
});

test('getSanitizedDbTarget strips credentials from url', () => {
  const target = getSanitizedDbTarget('postgresql://secret-user:super-secret@127.0.0.1:5432/devdb');
  assert.equal(target, '127.0.0.1:5432/devdb');
});
