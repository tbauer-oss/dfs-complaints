// api/_options.js
export const config = { runtime: 'nodejs22.x' };

export default async function handler(req, res) {
  // CORS-Header exakt wie in vercel.json (Origin & Allow-Liste)
  res.setHeader('Access-Control-Allow-Origin', 'https://dfs-complaints-web.vercel.app');
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate');
  res.setHeader('Access-Control-Max-Age', '600');

  // Preflight: kein Body nötig
  res.status(204).end();
}
