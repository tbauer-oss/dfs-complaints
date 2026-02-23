import test from 'node:test';
import assert from 'node:assert/strict';

import { __setRedisClientForTests, usersList } from '../_lib/store.js';

test('usersList returns only customer users from kv store and excludes portal/staff records', async (t) => {
  const entries = new Map([
    ['dfs:user:customer@example.com', {
      email: 'customer@example.com',
      contact: 'Customer User',
      lang: 'de',
    }],
    ['dfs:user:staff@example.com', {
      email: 'staff@example.com',
      type: 'staff',
      role: 'admin',
      portalStatus: 'active',
    }],
    ['dfs:user:portal-marker@example.com', {
      email: 'portal-marker@example.com',
      role: 'superuser',
    }],
  ]);

  const redisMock = {
    async keys(pattern) {
      assert.equal(pattern, 'dfs:user:*');
      return [...entries.keys()];
    },
    async get(key) {
      const value = entries.get(String(key));
      if (value == null) return null;
      return JSON.stringify(value);
    },
  };

  __setRedisClientForTests(redisMock);
  t.after(() => {
    __setRedisClientForTests(null);
  });

  const list = await usersList();
  assert.equal(list.length, 1);
  assert.equal(list[0].email, 'customer@example.com');
  assert.equal(list[0].type, 'customer');
  assert.equal(list[0].kind, 'customer');
});
