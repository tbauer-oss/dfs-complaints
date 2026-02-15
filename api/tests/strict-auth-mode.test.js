import test from 'node:test';
import assert from 'node:assert/strict';

import authLoginHandler from '../auth/login.js';
import portalLoginHandler from '../portal/login.js';
import { FORBIDDEN_EMAILS, forbiddenEmailReason } from '../_lib/forbiddenEmails.js';

function makeRes() {
  const out = { statusCode: 200, headers: {}, body: '' };
  const res = {
    status(code) { out.statusCode = code; return this; },
    setHeader(k, v) { out.headers[String(k).toLowerCase()] = v; },
    getHeader(k) { return out.headers[String(k).toLowerCase()]; },
    end(payload = '') { out.body = String(payload); return this; },
    __out: out,
  };
  Object.defineProperty(res, 'statusCode', {
    get() { return out.statusCode; },
    set(value) { out.statusCode = Number(value) || out.statusCode; },
  });
  return res;
}

test('forbidden email policy blocks explicit list and suspicious patterns', () => {
  for (const email of FORBIDDEN_EMAILS) {
    assert.ok(forbiddenEmailReason(email), `expected forbidden reason for ${email}`);
  }
  assert.equal(forbiddenEmailReason('legacy.user@dfs-diamon.de'), 'forbidden_legacy_prefix');
  assert.equal(forbiddenEmailReason('real+invalid@dfs-diamon.de'), 'forbidden_invalid_marker');
  assert.equal(forbiddenEmailReason('person@example.com'), 'forbidden_example_domain');
  assert.equal(forbiddenEmailReason('valid.user@dfs-diamon.de'), null);
});

test('auth/login denies forbidden emails with HTTP 403', async () => {
  const req = {
    method: 'POST',
    url: '/api/auth/login',
    headers: { origin: 'https://dfs-complaints-web.vercel.app' },
    body: { email: 'legacy.portal@dfs-diamon.de', password: 'irrelevant' },
  };
  const res = makeRes();

  await authLoginHandler(req, res);

  assert.equal(res.__out.statusCode, 403);
  assert.match(res.__out.body, /forbidden email/i);
});

test('portal/login denies forbidden emails with HTTP 403 and code', async () => {
  const req = {
    method: 'POST',
    url: '/api/portal/login',
    headers: {},
    body: { email: 'legacy.stale@dfs-diamon.de', password: 'irrelevant' },
  };
  const res = makeRes();

  await portalLoginHandler(req, res);

  assert.equal(res.__out.statusCode, 403);
  const payload = JSON.parse(res.__out.body || '{}');
  assert.equal(payload.code, 'FORBIDDEN_EMAIL');
});
