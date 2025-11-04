// /api/rep/me.js
import jwt from 'jsonwebtoken';

const REP_SECRET = process.env.REP_JWT_SECRET;

// Bearer-Token aus dem Authorization-Header extrahieren
function getBearerToken(req) {
  const h = req.headers.authorization || '';
  if (!h.toLowerCase().startsWith('bearer ')) return '';
  return h.slice(7).trim();
}

export default async function handler(req, res) {
  // ---- CORS (identisch wie in login.js) ----
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
    return res.status(204).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }
  if (!REP_SECRET) {
    return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET not set)' });
  }

  try {
    const token = getBearerToken(req);
    if (!token) {
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }

    // ✅ JWT prüfen
    const decoded = jwt.verify(token, REP_SECRET);

    // decoded enthält die Payload aus login.js (repId, email, firstName, lastName, region, role)
    // Hier könntest du später echte DB-Infos nachladen. Für jetzt reichen die Claims.
    const rep = {
      id:        decoded.repId || 'rep-secret',
      firstName: decoded.firstName || 'DFS',
      lastName:  decoded.lastName || 'Representative',
      email:     decoded.email || 'rep@dfs-diamon.de',
      region:    decoded.region || 'DACH',
      customers: [], // später per DB befüllen
    };

    return res.status(200).end(JSON.stringify(rep));
  } catch (e) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }
}