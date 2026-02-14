import jwt from 'jsonwebtoken';
import test from 'node:test';
import assert from 'node:assert/strict';

function makeReq({ method = 'GET', headers = {} } = {}) {
  return {
    method,
    headers: {
      origin: 'https://dfs-complaints-web.vercel.app',
      ...headers,
    },
    body: {},
    query: {},
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

test('portal auth health endpoint is DEV-only', async () => {
  const prevNodeEnv = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';

  try {
    const { default: healthHandler } = await import(`../portal/auth/health.js?prod=${Date.now()}`);
    const req = makeReq();
    const res = makeRes();

    await healthHandler(req, res);

    assert.equal(res.__out.statusCode, 404);
  } finally {
    if (prevNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = prevNodeEnv;
  }
});

test('portal auth health endpoint requires admin and returns boolean health flags in dev', async () => {
  const prevNodeEnv = process.env.NODE_ENV;
  const prevJwtSecret = process.env.JWT_SECRET;

  process.env.NODE_ENV = 'development';
  process.env.JWT_SECRET = 'devsecret';

  try {
    const { default: healthHandler } = await import(`../portal/auth/health.js?dev=${Date.now()}`);
    const token = jwt.sign({ email: 'admin@dfs-diamon.de', role: 'superuser', portalStatus: 'active' }, 'devsecret');
    const req = makeReq({ headers: { authorization: `Bearer ${token}` } });
    const res = makeRes();

    await healthHandler(req, res);

    assert.equal(res.__out.statusCode, 200);
    const payload = JSON.parse(res.__out.body || '{}');
    assert.equal(typeof payload.dbConnected, 'boolean');
    assert.equal(typeof payload.jwtSecretSet, 'boolean');
    assert.equal(payload.jwtSecretSet, true);
  } finally {
    if (prevNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = prevNodeEnv;
    if (prevJwtSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = prevJwtSecret;
  }
});
