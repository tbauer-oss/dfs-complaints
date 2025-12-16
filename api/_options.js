// api/_options.js
const PROD_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const LOCAL_ORIGIN = /^http:\/\/localhost(?::\d+)?$/i;

function setCorsHeaders(req, res) {
  const origin = req?.headers?.origin || '';
  const allowOrigin = origin === PROD_ORIGIN || LOCAL_ORIGIN.test(origin) ? origin : PROD_ORIGIN;

  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');
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

