import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';

import { __setDbForTests } from '../_lib/db.js';
import tourSeenHandler from '../portal/tour/seen.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

function makeReq({ method = 'POST', body = {}, headers = {} } = {}) {
  return {
    method,
    headers: {
      origin: 'https://dfs-complaints-web.vercel.app',
      authorization: `Bearer ${jwt.sign({ email: 'tour.user@dfs-diamon.de', role: 'user', portalStatus: 'active' }, JWT_SECRET)}`,
      'content-type': 'application/json',
      ...headers,
    },
    body,
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

test('POST /api/portal/tour/seen marks tour as seen for authenticated portal user', async () => {
  __setDbForTests({
    async query(sql) {
      if (String(sql).includes('FROM portal_users')) {
        return {
          rows: [{
            id: 'u1',
            email: 'tour.user@dfs-diamon.de',
            email_norm: 'tour.user@dfs-diamon.de',
            password_hash: 'hash',
            role: 'user',
            is_active: true,
            tour_seen: false,
            tour_seen_at: null,
          }],
        };
      }
      if (String(sql).includes('UPDATE portal_users')) {
        return {
          rows: [{
            id: 'u1',
            email: 'tour.user@dfs-diamon.de',
            email_norm: 'tour.user@dfs-diamon.de',
            password_hash: 'hash',
            role: 'user',
            is_active: true,
            tour_seen: true,
            tour_seen_at: new Date().toISOString(),
          }],
        };
      }
      return { rows: [] };
    },
  });

  const req = makeReq({ body: { seen: true } });
  const res = makeRes();

  await tourSeenHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.ok, true);
  assert.equal(payload.tourSeen, true);
});

test('POST /api/portal/tour/seen returns 401 for missing token', async () => {
  const req = makeReq({ headers: { authorization: '' } });
  const res = makeRes();

  await tourSeenHandler(req, res);

  assert.equal(res.__out.statusCode, 401);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.code, 'UNAUTHORIZED');
});
