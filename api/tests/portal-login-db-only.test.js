import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';

import { __setDbForTests } from '../_lib/db.js';
import loginHandler from '../portal/login.js';
import diagHandler from '../admin/auth-diagnose.js';

function makeReq({ method = 'POST', body = {}, query = {}, headers = {} } = {}) {
  return {
    method,
    headers: {
      origin: 'https://dfs-complaints-web.vercel.app',
      'content-type': 'application/json',
      ...headers,
    },
    body,
    query,
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

test('portal login returns STORE_UNAVAILABLE when DATABASE_URL/db is unavailable', async () => {
  __setDbForTests({
    async query() {
      const err = new Error('DATABASE_URL is not configured');
      err.code = 'DB_UNAVAILABLE';
      throw err;
    },
  });

  const req = makeReq({ body: { email: 'portal@dfs-diamon.de', password: 'Secret#123' } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 503);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.code, 'STORE_UNAVAILABLE');
});

test('portal login accepts legacy $2y$ hashes from portal_users', async () => {
  const password = 'Secret#123';
  const hash = await bcrypt.hash(password, 8);
  const twoYHash = `$2y$${hash.slice(4)}`;
  __setDbForTests({
    async query() {
      return {
        rows: [{
          id: 'u-1',
          email: 'portal@dfs-diamon.de',
          email_norm: 'portal@dfs-diamon.de',
          password_hash: twoYHash,
          role: 'user',
          is_active: true,
          tour_seen: false,
          tour_seen_at: null,
        }],
      };
    },
  });

  const req = makeReq({ body: { email: ' Portal@dfs-diamon.de ', password } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
});

test('portal login returns PASSWORD_NOT_SET when password hash is missing', async () => {
  __setDbForTests({
    async query() {
      return {
        rows: [{
          id: 'u-2',
          email: 'portal@dfs-diamon.de',
          email_norm: 'portal@dfs-diamon.de',
          password_hash: '',
          role: 'user',
          is_active: true,
          tour_seen: false,
          tour_seen_at: null,
        }],
      };
    },
  });

  const req = makeReq({ body: { email: 'portal@dfs-diamon.de', password: 'any' } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 409);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.code, 'PASSWORD_NOT_SET');
});

test('portal login returns ACCOUNT_DISABLED when user is inactive', async () => {
  const hash = await bcrypt.hash('Secret#123', 8);
  __setDbForTests({
    async query() {
      return {
        rows: [{
          id: 'u-4',
          email: 'inactive@dfs-diamon.de',
          email_norm: 'inactive@dfs-diamon.de',
          password_hash: hash,
          role: 'user',
          is_active: false,
          tour_seen: false,
          tour_seen_at: null,
        }],
      };
    },
  });

  const req = makeReq({ body: { email: 'inactive@dfs-diamon.de', password: 'Secret#123' } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 403);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.code, 'ACCOUNT_DISABLED');
});

test('portal login returns user-scoped tourSeen in payload', async () => {
  const password = 'Seen#123';
  const hash = await bcrypt.hash(password, 8);
  __setDbForTests({
    async query() {
      return {
        rows: [{
          id: 'u-tour',
          email: 'tour@dfs-diamon.de',
          email_norm: 'tour@dfs-diamon.de',
          password_hash: hash,
          role: 'user',
          is_active: true,
          tour_seen: true,
          tour_seen_at: new Date().toISOString(),
        }],
      };
    },
  });

  const req = makeReq({ body: { email: 'tour@dfs-diamon.de', password } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.tourSeen, true);
  assert.equal(payload.profile?.tourSeen, true);
});

test('auth diagnose endpoint is admin-secret protected and masks hash data', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'diag-secret';

  __setDbForTests({
    async query(sql) {
      if (String(sql).includes('SELECT id, email, email_norm, password_hash')) {
        return {
          rows: [{
            id: 'u-3',
            email: 'portal@dfs-diamon.de',
            email_norm: 'portal@dfs-diamon.de',
            password_hash: '$2b$10$ABCDEFGHIJKLMNOPQRSTUV1234567890abcdefghijklmn',
            role: 'admin',
            is_active: true,
            updated_at: '2026-01-01T10:00:00.000Z',
          }],
        };
      }
      if (String(sql).includes('SELECT COUNT(*)::int AS cnt FROM kv_store')) {
        return { rows: [{ cnt: 1 }] };
      }
      return { rows: [] };
    },
  });

  try {
    const req = makeReq({
      method: 'GET',
      query: { email: ' portal@dfs-diamon.de ' },
      headers: { 'x-admin-secret': 'diag-secret' },
    });
    const res = makeRes();

    await diagHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(payload.email_norm, 'portal@dfs-diamon.de');
    assert.equal(payload.existsInPortalUsers, true);
    assert.equal(payload.is_active, true);
    assert.equal(payload.hasPasswordHash, true);
    assert.equal(payload.passwordHashPrefix, '$2b$10$');
    assert.equal(payload.legacyKvExists, true);
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
  }
});


test('portal login clears legacy cache key and only stores safe cache payload', async () => {
  const password = 'SafeCache#123';
  const hash = await bcrypt.hash(password, 8);
  const queries = [];

  __setDbForTests({
    async query(sql, params = []) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      queries.push({ sql: normalized, params });
      if (normalized.includes('FROM public.portal_users')) {
        return {
          rows: [{
            id: 'u-cache',
            email: 'cache@dfs-diamon.de',
            email_norm: 'cache@dfs-diamon.de',
            password_hash: hash,
            role: 'admin',
            is_active: true,
            portal_status: 'active',
            tour_seen: true,
            created_at: '2026-01-01T00:00:00.000Z',
            updated_at: '2026-01-01T00:00:00.000Z',
          }],
        };
      }
      if (normalized.startsWith('DELETE FROM kv_store')) return { rowCount: 1, rows: [] };
      if (normalized.startsWith('INSERT INTO kv_store')) return { rowCount: 1, rows: [] };
      throw new Error(`unexpected query: ${normalized}`);
    },
  });

  const req = makeReq({ body: { email: 'cache@dfs-diamon.de', password } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);

  const deleteQuery = queries.find((q) => q.sql.startsWith('DELETE FROM kv_store'));
  assert.ok(deleteQuery);
  assert.deepEqual(deleteQuery.params, [['dfs:portal:user:cache@dfs-diamon.de']]);

  const cacheWrite = queries.find((q) => q.sql.startsWith('INSERT INTO kv_store'));
  assert.ok(cacheWrite);
  assert.equal(cacheWrite.params[0], 'dfs:portal:user_safe:cache@dfs-diamon.de');

  const cachePayload = JSON.parse(String(cacheWrite.params[1] || '{}'));
  assert.equal(cachePayload.__type, 'string');
  assert.equal(cachePayload.value.email_norm, 'cache@dfs-diamon.de');
  assert.equal(cachePayload.value.portal_status, 'active');
  assert.equal(Object.prototype.hasOwnProperty.call(cachePayload.value, 'password_hash'), false);
});
