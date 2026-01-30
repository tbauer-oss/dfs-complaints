// api/_options.js
const PROD_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const LOCAL_ORIGIN = /^http:\/\/localhost(?::\d+)?$/i;
const ALLOWED_ORIGINS = new Set([PROD_ORIGIN, 'http://localhost:3000', 'http://localhost:5173']);

function isAllowedOrigin(origin) {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  if (process.env.NODE_ENV !== 'production' && LOCAL_ORIGIN.test(origin)) return true;
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
