import test from 'node:test';
import assert from 'node:assert/strict';
import usersHandler from '../admin/push/users/index.js';
import deviceHandler from '../admin/push/devices/[deviceId].js';

function createMockRes() {
  const headers = new Map();
  return {
    statusCode: 200,
    headersSent: false,
    body: '',
    ended: false,
    setHeader(name, value) {
      headers.set(String(name).toLowerCase(), value);
    },
    getHeader(name) {
      return headers.get(String(name).toLowerCase());
    },
    end(payload = '') {
      this.body = String(payload);
      this.ended = true;
      this.headersSent = true;
    },
  };
}

test('admin push users endpoint requires auth', async () => {
  const req = {
    method: 'GET',
    headers: { origin: 'https://dfs-complaints-web.vercel.app' },
    query: {},
  };
  const res = createMockRes();

  await usersHandler(req, res);

  assert.ok(res.ended, 'expected response to end');
  assert.ok([401, 403].includes(res.statusCode), `expected auth failure, got ${res.statusCode}`);
});

test('admin push device toggle requires auth', async () => {
  const req = {
    method: 'PATCH',
    headers: { origin: 'https://dfs-complaints-web.vercel.app' },
    query: { deviceId: 'test-device' },
    body: { isDisabled: true },
  };
  const res = createMockRes();

  await deviceHandler(req, res);

  assert.ok(res.ended, 'expected response to end');
  assert.ok([401, 403].includes(res.statusCode), `expected auth failure, got ${res.statusCode}`);
});
