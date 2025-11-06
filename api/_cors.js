// api/_cors.js
export function corsHeaders(origin) {
  const allowlist = [
    'https://dfs-complaints-web.vercel.app',
    'http://localhost:3000',
    'http://localhost:5173',
    'http://localhost:5500',
  ];
  const allowOrigin = allowlist.includes(origin || '') 
    ? origin 
    : 'https://dfs-complaints-web.vercel.app';

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Vary': 'Origin',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Gate',
    'Access-Control-Max-Age': '600',
    // Nur einschalten, wenn du Cookies/Sessions brauchst. Für Bearer-Token NICHT nötig:
    // 'Access-Control-Allow-Credentials': 'true',
  };
}

export function handlePreflight(req, res) {
  const h = corsHeaders(req.headers.origin);
  if (req.method === 'OPTIONS') {
    res.status(204).setHeader('Content-Length', '0');
    Object.entries(h).forEach(([k, v]) => res.setHeader(k, v));
    res.end();
    return true;
  }
  Object.entries(h).forEach(([k, v]) => res.setHeader(k, v));
  return false;
}
