import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { portalUserSave, portalUserByEmail, userSave } from '../_lib/store.js';
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


test('portal login recovers admin auth from legacy customer hash when portal hash is stale', async () => {
  const [adminEmail] = [...ADMIN_EMAILS];
  const correctPassword = 'Recover#Admin1';
  const wrongPortalHash = await bcrypt.hash('Wrong#Pass1', 8);
  const customerHash = await bcrypt.hash(correctPassword, 8);

  await portalUserSave({
    email: adminEmail,
    passhash: wrongPortalHash,
    role: 'superuser',
    portalStatus: 'active',
    displayName: 'Broken Admin',
  });

  await userSave({
    email: adminEmail,
    passhash: customerHash,
    type: 'customer',
    kind: 'customer',
  });

  const req = makeReq({ email: adminEmail, password: correctPassword });
  const res = makeRes();
  await loginHandler(req, res);

  assert.equal(res.__out.statusCode, 200);
  const stored = await portalUserByEmail(adminEmail);
  assert.ok(stored?.passhash);
  assert.equal(await bcrypt.compare(correctPassword, stored.passhash), true);
});
