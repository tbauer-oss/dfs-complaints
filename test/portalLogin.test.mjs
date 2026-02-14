import test from 'node:test';
import assert from 'node:assert/strict';
import portalLoginHandler from '../api/portal/login.js';
import { __setRedisClientForTests, portalUserSave } from '../api/_lib/store.js';

function createMockRes() {
  return {
    statusCode: 200,
    headers: {},
    body: '',
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    getHeader(name) {
      return this.headers[name.toLowerCase()];
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    end(chunk = '') {
      this.body = String(chunk || '');
      return this;
    },
  };
}

test('portal login accepts legacy plaintext password and migrates it', async () => {
  const email = `legacy.portal.${Date.now()}@example.com`;
  const password = 'LegacySecret123!';

  await portalUserSave({
    email,
    password,
    role: 'admin',
    portalStatus: 'active',
    displayName: 'Legacy User',
  });

  const req = {
    method: 'POST',
    headers: {},
    body: { email, password },
  };
  const res = createMockRes();

  await portalLoginHandler(req, res);

  assert.equal(res.statusCode, 200);
  const decoded = JSON.parse(res.body);
  assert.equal(Boolean(decoded?.token), true);
  assert.equal(decoded?.profile?.email, email);
});


test('portal login accepts legacy plaintext passhash and migrates it', async () => {
  const email = `legacy.portal.passhash.${Date.now()}@example.com`;
  const password = 'LegacyPasshash123!';

  await portalUserSave({
    email,
    passhash: password,
    role: 'admin',
    portalStatus: 'active',
    displayName: 'Legacy Passhash User',
  });

  const req = {
    method: 'POST',
    headers: {},
    body: { email, password },
  };
  const res = createMockRes();

  await portalLoginHandler(req, res);

  assert.equal(res.statusCode, 200);
  const decoded = JSON.parse(res.body);
  assert.equal(Boolean(decoded?.token), true);
  assert.equal(decoded?.profile?.email, email);
});

test('portal login maps Upstash limit errors to 429 RATE_LIMITED', async () => {
  __setRedisClientForTests({
    async get() {
      throw new Error('ERR max requests limit exceeded. Limit: 500000, Usage: 500000');
    },
  });

  const req = {
    method: 'POST',
    headers: {},
    body: { email: 'limit@example.com', password: 'secret' },
  };
  const res = createMockRes();

  await portalLoginHandler(req, res);

  __setRedisClientForTests(null);
  assert.equal(res.statusCode, 429);
  const payload = JSON.parse(res.body);
  assert.equal(payload.code, 'RATE_LIMITED');
});

test('portal login maps store unavailable errors to 503 STORE_UNAVAILABLE', async () => {
  __setRedisClientForTests({
    async get() {
      throw new Error('connect ETIMEDOUT 1.2.3.4:443');
    },
  });

  const req = {
    method: 'POST',
    headers: {},
    body: { email: 'down@example.com', password: 'secret' },
  };
  const res = createMockRes();

  await portalLoginHandler(req, res);

  __setRedisClientForTests(null);
  assert.equal(res.statusCode, 503);
  const payload = JSON.parse(res.body);
  assert.equal(payload.code, 'STORE_UNAVAILABLE');
});

test('portal login still returns 401 INVALID_CREDENTIALS for password mismatch', async () => {
  const email = `wrong.pw.${Date.now()}@example.com`;
  await portalUserSave({
    email,
    passhash: 'not-the-password',
    role: 'admin',
    portalStatus: 'active',
  });

  const req = {
    method: 'POST',
    headers: {},
    body: { email, password: 'different-password' },
  };
  const res = createMockRes();

  await portalLoginHandler(req, res);

  assert.equal(res.statusCode, 401);
  const payload = JSON.parse(res.body);
  assert.equal(payload.code, 'INVALID_CREDENTIALS');
});
