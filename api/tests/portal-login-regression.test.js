import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { __setRedisClientForTests, portalUserSave, portalUserByEmail, userSave } from '../_lib/store.js';
import { ensureInitialAdmins, resolvePortalPasshash, ADMIN_EMAILS } from '../_lib/portalAuth.js';
import loginHandler from '../portal/login.js';

test('resolvePortalPasshash prefers existing passhash, then legacy passwordHash, then seeded hash', () => {
  assert.equal(resolvePortalPasshash({ passhash: 'a', passwordHash: 'b' }, 'c'), 'a');
  assert.equal(resolvePortalPasshash({ passwordHash: 'b' }, 'c'), 'b');
  assert.equal(resolvePortalPasshash({}, 'c'), 'c');
});


test('resolvePortalPasshash supports legacy passHash field', () => {
  assert.equal(resolvePortalPasshash({ passHash: 'legacy-camel' }, ''), 'legacy-camel');
});

test('ensureInitialAdmins preserves legacy passwordHash for admin accounts', async () => {
  const [adminEmail] = [...ADMIN_EMAILS];
  const legacyPassword = 'Legacy#Password1';
  const legacyHash = await bcrypt.hash(legacyPassword, 8);

  await portalUserSave({
    email: adminEmail,
    passwordHash: legacyHash,
    role: 'superuser',
    portalStatus: 'active',
    displayName: 'Legacy Admin',
  });

  await ensureInitialAdmins();
  const stored = await portalUserByEmail(adminEmail);

  assert.ok(stored);
  assert.ok(stored.passhash, 'passhash should be present after migration');
  assert.equal(await bcrypt.compare(legacyPassword, stored.passhash), true);
});


function makeReq(body) {
  return {
    method: 'POST',
    headers: { origin: 'https://dfs-complaints-web.vercel.app', 'content-type': 'application/json' },
    body,
    query: {},
  };
}

function makeRes() {
  const out = { statusCode: 200, headers: {}, body: '' };
  return {
    status(code) { out.statusCode = code; return this; },
    setHeader(k, v) { out.headers[String(k).toLowerCase()] = v; },
    getHeader(k) { return out.headers[String(k).toLowerCase()]; },
    end(payload = '') { out.body = payload; return this; },
    json(payload) { out.body = JSON.stringify(payload); return this; },
    __out: out,
  };
}





test('portal login migrates legacy internal user record from customer store', async () => {
  const email = 'legacy.portal@dfs-diamon.de';
  const password = 'LegacyPortal#123';
  const passhash = await bcrypt.hash(password, 8);
  await userSave({ email, passhash, contact: 'Legacy Portal User', role: 'admin' });

  const req = makeReq({ email, password });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const migrated = await portalUserByEmail(email);
  assert.ok(migrated);
  assert.equal(await bcrypt.compare(password, String(migrated?.passhash || '')), true);

});




test('portal login migrates legacy portal-like users even outside dfs-diamon domain', async () => {
  const email = 'legacy.staff@example.com';
  const password = 'LegacyStaff#123';
  await userSave({
    email,
    passhash: await bcrypt.hash(password, 8),
    role: 'admin',
    type: 'staff',
  });

  const req = makeReq({ email, password });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const migrated = await portalUserByEmail(email);
  assert.ok(migrated?.passhash);
  assert.equal(await bcrypt.compare(password, String(migrated.passhash || '')), true);
});


test('portal login migrates legacy users with explicit role user outside dfs domain', async () => {
  const email = 'legacy.role-user@example.com';
  const password = 'RoleUser#123';
  await userSave({
    email,
    passhash: await bcrypt.hash(password, 8),
    role: 'user',
  });

  const req = makeReq({ email, password });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const migrated = await portalUserByEmail(email);
  assert.ok(migrated?.passhash);
  assert.equal(await bcrypt.compare(password, String(migrated.passhash || '')), true);
});
test('portal login falls back to legacy user store when portal hash is stale', async () => {
  const email = 'legacy.stale@dfs-diamon.de';
  const validPassword = 'ValidLegacy#123';
  const stalePassword = 'StalePortal#123';

  await portalUserSave({
    email,
    passhash: await bcrypt.hash(stalePassword, 8),
    role: 'user',
    portalStatus: 'active',
  });
  await userSave({
    email,
    passhash: await bcrypt.hash(validPassword, 8),
    role: 'admin',
  });

  const req = makeReq({ email, password: validPassword });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const migrated = await portalUserByEmail(email);
  assert.ok(migrated?.passhash);
  assert.equal(await bcrypt.compare(validPassword, String(migrated.passhash || '')), true);
});


test('portal login accepts accidental surrounding spaces in password input', async () => {
  const email = 'legacy.trimmed@dfs-diamon.de';
  const password = 'TrimmedSecret#123';
  await portalUserSave({
    email,
    passhash: await bcrypt.hash(password, 8),
    role: 'user',
    portalStatus: 'active',
  });

  const req = makeReq({ email, password: ` ${password} ` });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
});
test('portal login supports legacy passHash field for bcrypt hashes', async () => {
  const email = 'legacy.camel@dfs-diamon.de';
  const password = 'LegacyCamel#123';
  const passHash = await bcrypt.hash(password, 8);
  await portalUserSave({ email, passHash, role: 'superuser', portalStatus: 'active' });

  const req = makeReq({ email, password });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const stored = await portalUserByEmail(email);
  assert.ok(stored?.passhash);
  assert.equal(await bcrypt.compare(password, stored.passhash), true);
});
test('portal login supports legacy plaintext password field and upgrades hash', async () => {
  const email = 'legacy.plaintext@dfs-diamon.de';
  const password = 'Plaintext#123';
  await portalUserSave({ email, password, role: 'superuser', portalStatus: 'active' });

  const req = makeReq({ email, password });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const stored = await portalUserByEmail(email);
  assert.ok(stored?.passhash);
  assert.equal(await bcrypt.compare(password, stored.passhash), true);
});


test('portal login accepts ADMIN_SECRET for admin email and repairs hash', async () => {
  const [adminEmail] = [...ADMIN_EMAILS];
  const previous = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'Emergency#AdminSecret1';
  try {
    await portalUserSave({
      email: adminEmail,
      passhash: await bcrypt.hash('Different#Password1', 8),
      role: 'superuser',
      portalStatus: 'active',
    });

    const req = makeReq({ email: adminEmail, password: 'Emergency#AdminSecret1' });
    const res = makeRes();
    await loginHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    const stored = await portalUserByEmail(adminEmail);
    assert.ok(stored?.passhash);
    assert.equal(await bcrypt.compare('Emergency#AdminSecret1', stored.passhash), true);
  } finally {
    if (previous === undefined) delete process.env.ADMIN_SECRET;
    else process.env.ADMIN_SECRET = previous;
  }
});

test('portal login finds legacy mixed-case redis keys and migrates them', async () => {
  const password = 'LegacyCase#123';
  const hash = await bcrypt.hash(password, 8);
  const legacyKey = 'dfs:portal:user:Case.User@dfs-diamon.de';
  const store = new Map([
    [legacyKey, { email: 'Case.User@dfs-diamon.de', passhash: hash, role: 'user', portalStatus: 'active' }],
  ]);

  __setRedisClientForTests({
    async get(key) { return store.get(key) ?? null; },
    async set(key, value) { store.set(key, value); return 'ok'; },
    async del(key) { store.delete(key); return 1; },
    async keys(pattern) {
      if (pattern === 'dfs:portal:user:*') return [...store.keys()];
      return [];
    },
  });

  try {
    const req = makeReq({ email: 'case.user@dfs-diamon.de', password });
    const res = makeRes();
    await loginHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    assert.equal(store.has('dfs:portal:user:case.user@dfs-diamon.de'), true);
    assert.equal(store.has(legacyKey), false);

    const migrated = await portalUserByEmail('case.user@dfs-diamon.de');
    assert.ok(migrated);
    assert.equal(String(migrated?.email || ''), 'case.user@dfs-diamon.de');
  } finally {
    __setRedisClientForTests(null);
  }
});

test('portal login does not return 500 when legacy key scan fails', async () => {
  __setRedisClientForTests({
    async get() { return null; },
    async set() { return 'ok'; },
    async del() { return 1; },
    async keys() { throw new Error('ERR unknown command KEYS'); },
    async scan() { throw new Error('scan disabled'); },
  });

  try {
    const req = makeReq({ email: 'notfound@dfs-diamon.de', password: 'Nope#123' });
    const res = makeRes();
    await loginHandler(req, res);

    assert.notEqual(res.__out.statusCode, 500);
  } finally {
    __setRedisClientForTests(null);
  }
});
