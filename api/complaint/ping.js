// api/complaint/ping.js
export const config = { runtime: 'nodejs' };

export default function handler(req, res) {
  // Minimal-CORS inline (kein Import)
  const origin = req.headers?.origin || 'https://dfs-complaints-web.vercel.app';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate');
  res.setHeader('Access-Control-Max-Age', '600');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    return res.end();
  }

  res.statusCode = 200;
  res.end(JSON.stringify({ ok: true, route: '/api/complaint/ping' }));
}
