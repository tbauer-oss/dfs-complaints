import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

import { __setDbForTests } from '../_lib/db.js';
import handler from '../account/password.js';

function makeReq({ body = {}, headers = {}, method = 'POST' } = {}) {
  return {
    method,
    headers: {
      origin: 'https://dfs-complaints-web.vercel.app',
      authorization: `Bearer ${jwt.sign({ sub: 'u-1', email: 'cache@dfs-diamon.de' }, process.env.JWT_SECRET || 'devsecret')}`,
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

test('password change invalidates legacy and safe portal user cache keys', async () => {
  const currentPassword = 'Current#123';
  const currentHash = await bcrypt.hash(currentPassword, 8);
  const seen = [];

  __setDbForTests({
    async query(sql, params = []) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      seen.push({ sql: normalized, params });

      if (normalized.includes('SELECT id, email_norm, password_hash')) {
        return { rows: [{ id: 'u-1', email_norm: 'cache@dfs-diamon.de', password_hash: currentHash }] };
      }
      if (normalized.startsWith('UPDATE portal_users')) {
        return { rowCount: 1, rows: [] };
      }
      if (normalized.startsWith('DELETE FROM kv_store')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`unexpected query: ${normalized}`);
    },
  });

  const req = makeReq({
    body: {
      currentPassword,
      newPassword: 'NewPassword#123',
    },
  });
  const res = makeRes();

  await handler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const deletes = seen.filter((entry) => entry.sql.startsWith('DELETE FROM kv_store'));
  const deletedKeys = deletes.map((entry) => entry.params?.[0]?.[0]).filter(Boolean);
  assert.ok(deletedKeys.includes('dfs:portal:user:cache@dfs-diamon.de'));
  assert.ok(deletedKeys.includes('dfs:portal:user_safe:cache@dfs-diamon.de'));
  assert.ok(deletedKeys.includes('dfs:users'));
  assert.ok(deletedKeys.includes('dfs:userDirectory'));
  assert.ok(deletedKeys.includes('dfs:roles'));
});

test('password change accepts legacy $2y$ hashes without returning 500', async () => {
  const currentPassword = 'Current#123';
  const bcryptHash = await bcrypt.hash(currentPassword, 8);
  const legacyHash = `$2y$${bcryptHash.slice(4)}`;

  __setDbForTests({
    async query(sql) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      if (normalized.includes('SELECT id, email_norm, password_hash')) {
        return { rows: [{ id: 'u-1', email_norm: 'cache@dfs-diamon.de', password_hash: legacyHash }] };
      }
      if (normalized.startsWith('UPDATE portal_users')) {
        return { rowCount: 1, rows: [] };
      }
      if (normalized.startsWith('DELETE FROM kv_store')) {
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`unexpected query: ${normalized}`);
    },
  });

  const req = makeReq({
    body: {
      currentPassword,
      newPassword: 'NewPassword#123',
    },
  });
  const res = makeRes();

  await handler(req, res);

  assert.equal(res.__out.statusCode, 200);
});
