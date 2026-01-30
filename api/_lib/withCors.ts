// api/_lib/withCors.ts
const ALLOWED_ORIGINS = new Set([
  'https://dfs-complaints-web.vercel.app',
  'http://localhost:3000',
]);

const ALLOWED_METHODS = 'GET,POST,PUT,PATCH,DELETE,OPTIONS';
const ALLOWED_HEADERS = 'Authorization, Content-Type';
const MAX_AGE = '86400';

function normalizeOrigin(origin) {
  if (!origin) return '';
  try {
    return new URL(origin).origin;
  } catch {
    return String(origin).trim();
  }
}

function resolveAllowedOrigin(origin) {
  const normalized = normalizeOrigin(origin);
  return ALLOWED_ORIGINS.has(normalized) ? normalized : '';
}

function applyCorsHeaders(res, allowOrigin) {
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', ALLOWED_METHODS);
  res.setHeader('Access-Control-Allow-Headers', ALLOWED_HEADERS);
  res.setHeader('Access-Control-Max-Age', MAX_AGE);
  if (allowOrigin) {
    res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  }
}

export function withCors(handler, options = {}) {
  return async function corsWrapped(req, res) {
    const allowOrigin = resolveAllowedOrigin(req?.headers?.origin || '');
    applyCorsHeaders(res, allowOrigin);

    if (typeof options.before === 'function') {
      options.before(req, res, { allowOrigin });
    }

    if (req.method === 'OPTIONS') {
      res.statusCode = 204;
      res.end();
      return;
    }

    try {
      await handler(req, res);
    } catch (err) {
      if (!res.headersSent) {
        res.statusCode = 500;
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.end(JSON.stringify({ error: 'server error' }));
      } else {
        res.end();
      }
    }
  };
}
