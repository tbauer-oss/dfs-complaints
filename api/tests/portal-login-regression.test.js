import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { portalUserSave, portalUserByEmail } from '../_lib/store.js';
import { ensureInitialAdmins, resolvePortalPasshash, ADMIN_EMAILS } from '../_lib/portalAuth.js';

test('resolvePortalPasshash prefers existing passhash, then legacy passwordHash, then seeded hash', () => {
  assert.equal(resolvePortalPasshash({ passhash: 'a', passwordHash: 'b' }, 'c'), 'a');
  assert.equal(resolvePortalPasshash({ passwordHash: 'b' }, 'c'), 'b');
  assert.equal(resolvePortalPasshash({}, 'c'), 'c');
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
