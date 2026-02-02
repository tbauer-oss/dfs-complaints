import test from 'node:test';
import assert from 'node:assert/strict';
import loginHandler from '../auth/login.js';

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

test('auth/login returns JSON with CORS headers on auth errors', async () => {
  const req = {
    method: 'POST',
    headers: { origin: 'https://dfs-complaints-web.vercel.app' },
    body: { email: 'nobody@example.com', password: 'bad-password' },
  };
  const res = createMockRes();

  await loginHandler(req, res);

  assert.ok(res.ended, 'expected handler to end the response');
  assert.match(res.body, /\{.+\}/, 'expected a JSON response body');
  assert.match(String(res.getHeader('content-type')), /application\/json/i);
  assert.ok(res.getHeader('access-control-allow-origin'));
  assert.ok([400, 401, 403].includes(res.statusCode));
});
