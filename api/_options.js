// api/_options.js
export const config = { runtime: 'nodejs22.x' };

export default function handler(req, res) {
  // Nur Preflight beantworten
  res.statusCode = 204;

  // Gleiche Header wie in vercel.json (nicht schaden, doppelt ist ok)
  res.setHeader('Access-Control-Allow-Origin', 'https://dfs-complaints-web.vercel.app');
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate');
  res.setHeader('Access-Control-Max-Age', '600');

  return res.end();
}
