export function applyAdminCors(req, res) {
  const origin = req?.headers?.origin || '';
  const isProd = origin === 'https://dfs-complaints-web.vercel.app';
  const isLocalhost = /^https?:\/\/localhost(?::\d+)?$/i.test(origin);
  if (isProd || isLocalhost) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
  res.setHeader('Access-Control-Max-Age', '86400');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return true;
  }
  return false;
}
