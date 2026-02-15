import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';

import { __setDbForTests } from '../_lib/db.js';
import loginHandler from '../portal/login.js';
import diagHandler from '../admin/diag-portal-user.js';

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

  const req = makeReq({ body: { email: 'portal@dfs-diamon.de', password } });
  const res = makeRes();

  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
});

test('portal login returns INVALID_CREDENTIALS when password hash is missing', async () => {
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

  assert.equal(res.__out.statusCode, 401);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.code, 'INVALID_CREDENTIALS');
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

test('diag portal user endpoint is admin-secret protected and masks hash data', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'diag-secret';

  __setDbForTests({
    async query() {
      return {
        rows: [{
          id: 'u-3',
          email: 'portal@dfs-diamon.de',
          email_norm: 'portal@dfs-diamon.de',
          password_hash: '$2b$10$ABCDEFGHIJKLMNOPQRSTUV1234567890abcdefghijklmn',
          role: 'admin',
          is_active: true,
        }],
      };
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
    assert.equal(payload.found, true);
    assert.equal(payload.role, 'admin');
    assert.equal(payload.is_active, true);
    assert.equal(payload.hash_prefix, '$2b$');
    assert.equal(typeof payload.hash_len, 'number');
  } finally {
    if (previousSecret === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previousSecret;
  }
});
