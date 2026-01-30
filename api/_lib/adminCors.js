export function applyAdminCors(req, res) {
  const origin = req.headers.origin || '';
  const allowed = new Set([
    'https://dfs-complaints-web.vercel.app',
    'http://localhost:3000',
    'http://localhost:5173',
  ]);
  const isLocalhost =
    process.env.NODE_ENV !== 'production' &&
    (origin.startsWith('http://localhost:') || origin.startsWith('https://localhost:'));

  if (allowed.has(origin) || isLocalhost) {
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
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return true;
  }
  return false;
}
