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

export function withCors(handler, {
  allowOrigin = '*', // kein Cookie-Flow → '*' ist ok
  allowMethods = 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
  allowHeaders = 'Content-Type, Authorization, X-Admin-Secret, X-Gate',
  maxAge = '600',
} = {}) {
  return async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', allowOrigin);
    res.setHeader('Access-Control-Allow-Methods', allowMethods);
    res.setHeader('Access-Control-Allow-Headers', allowHeaders);
    res.setHeader('Access-Control-Max-Age', maxAge);

    if (req.method === 'OPTIONS') {
      // Preflight sofort beenden
      return res.status(204).end();
    }

    // Normale Antworten: CORS-Header sind oben bereits gesetzt
    return handler(req, res);
  };
}
