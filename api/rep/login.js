// /api/rep/login.js
import jwt from 'jsonwebtoken';

const REP_SECRET = process.env.REP_JWT_SECRET;

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
    res.setHeader('Vary', 'Origin'); // wichtig für CDN-Caches
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

  if (!REP_SECRET) {
    return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET not set)' });
  }

  // Secret aus Header ODER Body akzeptieren (passt zum Client-Update)
  const headerSecret = req.headers['x-rep-secret'];
  const bodySecret =
    req.body && typeof req.body === 'object' ? (req.body.secret || '') : '';
  const secret = String(headerSecret || bodySecret || '').trim();

  if (!secret) {
    return res.status(400).json({ error: 'Missing secret' });
  }

  // ✅ Secret validieren
  if (secret !== REP_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  // ✅ Token erzeugen (Payload kann später mit echten Rep-Daten befüllt werden)
  const payload = {
    repId: 'rep-secret',                // Platzhalter (später aus DB)
    email: 'rep@dfs-diamon.de',         // Platzhalter
    firstName: 'DFS',
    lastName: 'Representative',
    region: 'DACH',
    role: 'rep',
  };

  const token = jwt.sign(payload, REP_SECRET, { expiresIn: '12h' });

  return res.status(200).json({ token });
}