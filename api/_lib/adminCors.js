export function applyAdminCors(req, res) {
  const origin = req.headers.origin || '';
  const allowed = [
    'https://dfs-complaints-web.vercel.app',
  ];
  const isLocalhost =
    origin.startsWith('http://localhost:') || origin.startsWith('https://localhost:');

  if (allowed.includes(origin) || isLocalhost) {
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
