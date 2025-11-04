// /api/rep/me.js
import jwt from 'jsonwebtoken';
import { loadRepById, repCustomers } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

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
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }
  if (!REP_SECRET) {
    return res.status(500).json({ error: 'server misconfig (REP_JWT_SECRET not set)' });
  }

  try {
    const token = getBearerToken(req);
    if (!token) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

    const claims = jwt.verify(token, REP_SECRET);
    const repId = claims?.repId;
    if (!repId) return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));

    const rep = await loadRepById(repId);
    if (!rep || rep.active === false) {
      return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
    }

    const customers = await repCustomers(rep.id);

    return res.status(200).end(
      JSON.stringify({
        id: rep.id,
        firstName: rep.firstName,
        lastName: rep.lastName,
        email: rep.email,
        region: rep.region,
        customers: customers || [],
      })
    );
  } catch {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }
}