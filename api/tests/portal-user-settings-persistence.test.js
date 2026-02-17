import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

import { __setDbForTests } from '../_lib/db.js';
import portalUsersHandler from '../portal/users.js';
import portalLoginHandler from '../portal/login.js';
import { portalUserByEmail } from '../_lib/store.js';

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret';

function makeReq({ method = 'GET', body = {}, headers = {}, query = {} } = {}) {
  return {
    method,
    body,
    query,
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

test('portal user settings persist in DB and remain after re-login', async () => {
  const password = 'Persist#123';
  const passwordHash = await bcrypt.hash(password, 8);

  const users = new Map();
  users.set('admin@dfs-diamon.de', {
    id: 'u-admin',
    email: 'admin@dfs-diamon.de',
    email_norm: 'admin@dfs-diamon.de',
    password_hash: passwordHash,
    role: 'superuser',
    is_active: true,
    display_name: 'Admin',
    is_sales: false,
    is_prrc: false,
    assigned_departments: [],
    tile_permissions: {},
    tour_seen: false,
    tour_seen_at: null,
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  });
  users.set('target@dfs-diamon.de', {
    id: 'u-target',
    email: 'target@dfs-diamon.de',
    email_norm: 'target@dfs-diamon.de',
    password_hash: passwordHash,
    role: 'user',
    is_active: true,
    display_name: 'Target User',
    is_sales: false,
    is_prrc: false,
    assigned_departments: [],
    tile_permissions: {},
    tour_seen: false,
    tour_seen_at: null,
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  });

  const kvStore = new Map();

  __setDbForTests({
    async query(sql, params = []) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();

      if (normalized.includes('FROM public.portal_users') && normalized.includes('WHERE email_norm = $1')) {
        const row = users.get(String(params[0] || '').toLowerCase());
        return { rows: row ? [{ ...row }] : [] };
      }

      if (normalized.startsWith('INSERT INTO portal_users') && normalized.includes('ON CONFLICT (email_norm)')) {
        const [email, emailNorm, hashMaybe, role, isActive, displayName, isSales, isPrrc, assignedDepartments, tilePermissions] = params;
        const prev = users.get(String(emailNorm || '').toLowerCase());
        const next = {
          ...(prev || {}),
          id: prev?.id || `u-${emailNorm}`,
          email,
          email_norm: String(emailNorm || '').toLowerCase(),
          password_hash: hashMaybe || prev?.password_hash || '',
          role,
          is_active: isActive,
          display_name: displayName,
          is_sales: isSales === true,
          is_prrc: isPrrc === true,
          assigned_departments: JSON.parse(String(assignedDepartments || '[]')),
          tile_permissions: JSON.parse(String(tilePermissions || '{}')),
          tour_seen: prev?.tour_seen === true,
          tour_seen_at: prev?.tour_seen_at || null,
          created_at: prev?.created_at || '2026-01-01T00:00:00.000Z',
          updated_at: '2026-02-19T12:00:00.000Z',
        };
        users.set(next.email_norm, next);
        return { rows: [{ ...next }] };
      }

      if (normalized.startsWith('DELETE FROM kv_store WHERE k = ANY($1::text[])')) {
        for (const key of params[0] || []) kvStore.delete(key);
        return { rowCount: 1, rows: [] };
      }

      if (normalized.startsWith('INSERT INTO kv_store')) {
        kvStore.set(params[0], params[1]);
        return { rowCount: 1, rows: [] };
      }

      throw new Error(`unexpected query: ${normalized}`);
    },
  });

  const adminToken = jwt.sign({ sub: 'u-admin', email: 'admin@dfs-diamon.de', role: 'superuser', portalStatus: 'active' }, JWT_SECRET);
  const patchReq = makeReq({
    method: 'PATCH',
    headers: { authorization: `Bearer ${adminToken}` },
    body: {
      email: 'target@dfs-diamon.de',
      isPRRC: true,
      assignedDepartments: ['QM', 'Produktion'],
      tilePermissions: { complaints: 'write', users: 'read' },
    },
  });
  const patchRes = makeRes();
  await portalUsersHandler(patchReq, patchRes);

  assert.equal(patchRes.__out.statusCode, 200);
  const patched = JSON.parse(patchRes.__out.body || '{}');
  assert.equal(patched.isPRRC, true);
  assert.deepEqual(patched.assignedDepartments, ['QM', 'Produktion']);
  assert.deepEqual(patched.tilePermissions, { complaints: 'write', users: 'read' });

  const stored = await portalUserByEmail('target@dfs-diamon.de');
  assert.equal(stored?.isPRRC, true);
  assert.deepEqual(stored?.assignedDepartments, ['QM', 'Produktion']);
  assert.deepEqual(stored?.tilePermissions, { complaints: 'write', users: 'read' });

  const loginReq1 = makeReq({ method: 'POST', body: { email: 'target@dfs-diamon.de', password } });
  const loginRes1 = makeRes();
  await portalLoginHandler(loginReq1, loginRes1);
  assert.equal(loginRes1.__out.statusCode, 200);

  const loginReq2 = makeReq({ method: 'POST', body: { email: 'target@dfs-diamon.de', password } });
  const loginRes2 = makeRes();
  await portalLoginHandler(loginReq2, loginRes2);
  assert.equal(loginRes2.__out.statusCode, 200);

  const afterRelogin = await portalUserByEmail('target@dfs-diamon.de');
  assert.equal(afterRelogin?.isPRRC, true);
  assert.deepEqual(afterRelogin?.assignedDepartments, ['QM', 'Produktion']);
  assert.deepEqual(afterRelogin?.tilePermissions, { complaints: 'write', users: 'read' });
});


test('portal user PATCH writes assigned_departments as text[] when schema reports text array', async () => {
  const passwordHash = await bcrypt.hash('Secret#123', 8);
  const users = new Map();
  users.set('admin@dfs-diamon.de', {
    id: 'u-admin',
    email: 'admin@dfs-diamon.de',
    email_norm: 'admin@dfs-diamon.de',
    password_hash: passwordHash,
    role: 'superuser',
    is_active: true,
    display_name: 'Admin',
    is_sales: false,
    is_prrc: false,
    assigned_departments: ['QM'],
    tile_permissions: {},
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  });
  users.set('target@dfs-diamon.de', {
    id: 'u-target',
    email: 'target@dfs-diamon.de',
    email_norm: 'target@dfs-diamon.de',
    password_hash: passwordHash,
    role: 'user',
    is_active: true,
    display_name: 'Target',
    is_sales: false,
    is_prrc: false,
    assigned_departments: ['QM'],
    tile_permissions: {},
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  });

  let usedTextArrayCast = false;

  __setDbForTests({
    async query(sql, params = []) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      if (normalized.includes('FROM information_schema.columns')) {
        return {
          rows: [
            { column_name: 'assigned_departments', data_type: 'ARRAY', udt_name: '_text' },
            { column_name: 'display_name', data_type: 'text', udt_name: 'text' },
            { column_name: 'is_sales', data_type: 'boolean', udt_name: 'bool' },
            { column_name: 'is_prrc', data_type: 'boolean', udt_name: 'bool' },
            { column_name: 'tile_permissions', data_type: 'jsonb', udt_name: 'jsonb' },
          ],
        };
      }
      if (normalized.includes('FROM public.portal_users') && normalized.includes('WHERE email_norm = $1')) {
        const row = users.get(String(params[0] || '').toLowerCase());
        return { rows: row ? [{ ...row }] : [] };
      }
      if (normalized.startsWith('INSERT INTO portal_users') && normalized.includes('ON CONFLICT (email_norm)')) {
        usedTextArrayCast = normalized.includes('$9::text[]');
        const [email, emailNorm, hashMaybe, role, isActive, displayName, isSales, isPrrc, assignedDepartments] = params;
        const prev = users.get(String(emailNorm || '').toLowerCase());
        const next = {
          ...(prev || {}),
          id: prev?.id || 'u-target',
          email,
          email_norm: emailNorm,
          password_hash: hashMaybe || prev?.password_hash,
          role,
          is_active: isActive,
          display_name: displayName,
          is_sales: isSales === true,
          is_prrc: isPrrc === true,
          assigned_departments: Array.isArray(assignedDepartments) ? assignedDepartments : [],
          tile_permissions: {},
        };
        users.set(String(emailNorm).toLowerCase(), next);
        return { rows: [next] };
      }
      if (normalized.startsWith('DELETE FROM kv_store WHERE k = ANY($1::text[])')) return { rowCount: 1, rows: [] };
      throw new Error(`unexpected query: ${normalized}`);
    },
  });

  const adminToken = jwt.sign({ sub: 'u-admin', email: 'admin@dfs-diamon.de', role: 'superuser', portalStatus: 'active' }, JWT_SECRET);
  const patchReq = makeReq({
    method: 'PATCH',
    headers: { authorization: `Bearer ${adminToken}` },
    body: { email: 'target@dfs-diamon.de', assignedDepartments: ['QM', 'Produktion'] },
  });
  const patchRes = makeRes();
  await portalUsersHandler(patchReq, patchRes);

  assert.equal(patchRes.__out.statusCode, 200);
  assert.equal(usedTextArrayCast, true);
  const updated = await portalUserByEmail('target@dfs-diamon.de');
  assert.deepEqual(updated?.assignedDepartments, ['QM', 'Produktion']);
});
