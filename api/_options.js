// api/_options.js
const PROD_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const LOCAL_ORIGIN = /^http:\/\/localhost(?::\d+)?$/i;
const ALLOWED_ORIGINS = new Set([PROD_ORIGIN, 'http://localhost:3000', 'http://localhost:5173']);

function normalizeOrigin(origin) {
  if (!origin) return '';
  try {
    const url = new URL(origin);
    const isHttpsDefault = url.protocol === 'https:' && (url.port === '' || url.port === '443');
    const isHttpDefault = url.protocol === 'http:' && (url.port === '' || url.port === '80');
    if (isHttpsDefault || isHttpDefault) {
      return `${url.protocol}//${url.hostname}`;
    }
    return url.origin;
  } catch {
    return origin.trim().toLowerCase();
  }
}

function isAllowedOrigin(origin) {
  if (!origin) return false;
  const normalized = normalizeOrigin(origin);
  if (ALLOWED_ORIGINS.has(normalized)) return true;
  if (process.env.NODE_ENV !== 'production' && LOCAL_ORIGIN.test(normalized)) return true;
  return false;
}

function setCorsHeaders(req, res) {
  const origin = req?.headers?.origin || '';
  if (!isAllowedOrigin(origin)) return;

  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Requested-With, X-Admin-Secret, X-Gate'
  );
  res.setHeader('Access-Control-Max-Age', '86400');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
}

function handler(req, res) {
  try {
    setCorsHeaders(req, res);
  } catch (err) {
    console.error('[options] failed to set CORS headers', err);
    try {
      setCorsHeaders({}, res);
    } catch (_) {}
  }

  res.statusCode = 204;
  res.end();
}

module.exports = handler;
module.exports.config = { runtime: 'nodejs' };
