const PROD_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const LOCALHOST_PATTERN = /^https?:\/\/localhost(?::\d+)?$/i;

function resolveAdminOrigin(req) {
  const origin = req?.headers?.origin || '';
  if (origin === PROD_ORIGIN || LOCALHOST_PATTERN.test(origin)) return origin;
  return PROD_ORIGIN;
}

export function applyAdminCors(req, res) {
  const allowOrigin = resolveAdminOrigin(req);
  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
  res.setHeader('Access-Control-Max-Age', '86400');
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  return false;
}
