import test from 'node:test';
import assert from 'node:assert/strict';

import { __setDbForTests } from '../_lib/db.js';

function restoreAdminSecret(value) {
  if (value === undefined) delete process.env.ADMIN_SECRET;
  else process.env.ADMIN_SECRET = value;
}

test.afterEach(() => {
  __setDbForTests(null);
});

test('ensureInitialAdmins does not overwrite existing users and logs ADMIN_EXISTS_NOOP', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'Bootstrap#Secret1';

  const queries = [];
  __setDbForTests({
    async query(sql, params = []) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      queries.push({ sql: normalized, params });
      if (normalized.startsWith('SELECT id FROM public.portal_users')) {
        return { rows: [{ id: 'u-existing' }] };
      }
      if (normalized.startsWith('INSERT INTO public.portal_users')) {
        throw new Error('must not insert existing admin');
      }
      return { rows: [] };
    },
  });

  const seenLogs = [];
  const originalInfo = console.info;
  console.info = (...args) => {
    seenLogs.push(args);
  };

  try {
    const module = await import(`../_lib/portalAuth.js?test=${Date.now()}`);
    await module.ensureInitialAdmins();

    const selectCount = queries.filter((entry) => entry.sql.startsWith('SELECT id FROM public.portal_users')).length;
    assert.equal(selectCount, module.ADMIN_EMAILS.size);

    const insertCount = queries.filter((entry) => entry.sql.startsWith('INSERT INTO public.portal_users')).length;
    assert.equal(insertCount, 0);

    const noops = seenLogs.filter((entry) => entry[0] === '[portalAuth/ensureInitialAdmins]' && entry[1]?.outcome === 'ADMIN_EXISTS_NOOP');
    assert.equal(noops.length, module.ADMIN_EMAILS.size);
  } finally {
    console.info = originalInfo;
    restoreAdminSecret(previousSecret);
  }
});

test('ensureInitialAdmins creates missing admin users without upsert update path', async () => {
  const previousSecret = process.env.ADMIN_SECRET;
  process.env.ADMIN_SECRET = 'Bootstrap#Secret2';

  const queries = [];
  __setDbForTests({
    async query(sql, params = []) {
      const normalized = String(sql).replace(/\s+/g, ' ').trim();
      queries.push({ sql: normalized, params });
      if (normalized.startsWith('SELECT id FROM public.portal_users')) {
        return { rows: [] };
      }
      if (normalized.startsWith('INSERT INTO public.portal_users')) {
        return { rowCount: 1, rows: [] };
      }
      return { rows: [] };
    },
  });

  try {
    const module = await import(`../_lib/portalAuth.js?test=${Date.now()}-insert`);
    await module.ensureInitialAdmins();

    const inserts = queries.filter((entry) => entry.sql.startsWith('INSERT INTO public.portal_users'));
    assert.equal(inserts.length, module.ADMIN_EMAILS.size);
    for (const insert of inserts) {
      assert.equal(insert.sql.includes('ON CONFLICT'), false);
      assert.equal(insert.params.length, 3);
      assert.equal(insert.params[2].startsWith('$2'), true);
    }
  } finally {
    restoreAdminSecret(previousSecret);
  }
});
