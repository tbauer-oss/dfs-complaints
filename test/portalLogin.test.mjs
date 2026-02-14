import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from '../api/node_modules/bcryptjs/index.js';
import portalLoginHandler from '../api/portal/login.js';
import { __setDbForTests } from '../api/_lib/db.js';

function createMockRes() {
  return {
    statusCode: 200,
    headers: {},
    body: '',
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    getHeader(name) { return this.headers[name.toLowerCase()]; },
    status(code) { this.statusCode = code; return this; },
    end(chunk = '') { this.body = String(chunk || ''); return this; },
  };
}

test('valid login -> 200', async () => {
  const email = 'admin@example.com';
  const password = 'Secret123!';
  const hash = await bcrypt.hash(password, 10);

  __setDbForTests({
    async query(text, params) {
      assert.match(text, /from portal_users/i);
      assert.equal(params[0], email);
      return {
        rows: [{
          id: '11111111-1111-1111-1111-111111111111',
          email,
          email_norm: email,
          password_hash: hash,
          role: 'admin',
          is_active: true,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }],
      };
    },
  });

  const req = { method: 'POST', headers: {}, body: { email: '  ADMIN@example.com ', password } };
  const res = createMockRes();
  await portalLoginHandler(req, res);

  __setDbForTests(null);
  assert.equal(res.statusCode, 200);
  const payload = JSON.parse(res.body);
  assert.equal(typeof payload.token, 'string');
  assert.equal(payload.user.email, email);
});

test('invalid credentials -> 401 + INVALID_CREDENTIALS', async () => {
  const email = 'admin@example.com';
  const hash = await bcrypt.hash('another-password', 10);

  __setDbForTests({
    async query() {
      return {
        rows: [{
          id: '11111111-1111-1111-1111-111111111111',
          email,
          email_norm: email,
          password_hash: hash,
          role: 'admin',
          is_active: true,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }],
      };
    },
  });

  const req = { method: 'POST', headers: {}, body: { email, password: 'wrong' } };
  const res = createMockRes();
  await portalLoginHandler(req, res);

  __setDbForTests(null);
  assert.equal(res.statusCode, 401);
  const payload = JSON.parse(res.body);
  assert.equal(payload.code, 'INVALID_CREDENTIALS');
});

test('DB down -> 503 + STORE_UNAVAILABLE', async () => {
  __setDbForTests({
    async query() {
      throw new Error('connect ETIMEDOUT');
    },
  });

  const req = { method: 'POST', headers: {}, body: { email: 'admin@example.com', password: 'secret' } };
  const res = createMockRes();
  await portalLoginHandler(req, res);

  __setDbForTests(null);
  assert.equal(res.statusCode, 503);
  const payload = JSON.parse(res.body);
  assert.equal(payload.code, 'STORE_UNAVAILABLE');
});
