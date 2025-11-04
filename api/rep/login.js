// /api/rep/login.js
export default async function handler(req, res) {
  // ---- CORS (kleinstmöglicher Eingriff) ----
  const origin = req.headers.origin || '';
  const allow = [
    'https://dfs-complaints-web.vercel.app',
    'http://localhost:5173',
    'http://localhost:3000',
  ];
  if (allow.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret'
  );
  if (req.method === 'OPTIONS') {
    return res.status(204).end(); // Preflight: sofort raus
  }

  // ---- eigentliche Logik ----
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Secret aus Header ODER Body akzeptieren (passt zum Client-Update)
  const secret =
    req.headers['x-rep-secret'] ||
    (req.body && typeof req.body === 'object' ? req.body.secret : '');

  if (!secret) {
    return res.status(400).json({ error: 'Missing secret' });
  }

  // TODO: secret validieren -> token erzeugen
  // const token = sign(...);
  return res.status(200).json({ ok: true /*, token */ });
}