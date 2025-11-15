// /api/rep/me.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors } from '../_lib/cors.js';
import { loadRepById, repCustomers } from '../_lib/repsStore.js';

const REP_SECRET = process.env.REP_JWT_SECRET;

function getBearerToken(req) {
  const h = String(req.headers.authorization || '');
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
}

export default async function handler(req, res) {
  // Einheitliche CORS-Header
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }
  if (!REP_SECRET) {
    return res.status(500).end(JSON.stringify({ error: 'server misconfig (REP_JWT_SECRET not set)' }));
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

    return res.status(200).end(JSON.stringify({
      id:        rep.id,
      firstName: rep.firstName,
      lastName:  rep.lastName,
      email:     rep.email,
      region:    rep.region,
      lang:      rep.lang || 'de',
      customers: customers || [],
    }));
  } catch (err) {
    console.error('[rep/me] verify failed:', err);
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }
}
