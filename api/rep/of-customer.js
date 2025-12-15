// /api/rep/of-customer.js
export const config = { runtime: 'nodejs' };

import jwt from 'jsonwebtoken';
import { setCors } from '../_lib/cors.js';
import { loadRepById } from '../_lib/repsStore.js';

// --- Minimaler Upstash-GET (wie in rep/customers.js) ---
const UP_URL   = process.env.UPSTASH_REDIS_REST_URL  || '';
const UP_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || '';

async function upReq(path, { method = 'GET' } = {}) {
  if (!UP_URL || !UP_TOKEN) throw new Error('UPSTASH env missing');
  const r = await fetch(`${UP_URL}${path}`, {
    method,
    headers: { Authorization: `Bearer ${UP_TOKEN}` },
    cache: 'no-store',
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    const msg = j?.error || j?.message || `Upstash error ${r.status}`;
    throw new Error(msg);
  }
  return j?.result;
}

const KEY_REP_OF = (email) => `dfs:repOf:${email}`;

function bearer(req) {
  const h = String(req.headers.authorization || '');
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
}
const S = (v) => (v ?? '').toString().trim();
const norm = (v) => S(v).toLowerCase();

export default async function handler(req, res) {
  setCors(req, res, 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET')
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));

  // WICHTIG: Kunden-Login-Secret (nicht REP_JWT_SECRET)
  const APP_JWT_SECRET = process.env.APP_JWT_SECRET || process.env.JWT_SECRET;
  if (!APP_JWT_SECRET)
    return res.status(500).end(JSON.stringify({ error: 'APP_JWT_SECRET not set' }));

  try {
    // 1) Kunden-JWT prüfen & E-Mail extrahieren
    const token = bearer(req);
    if (!token) return res.status(401).end(JSON.stringify({ error: 'missing token' }));

    let claims;
    try { claims = jwt.verify(token, APP_JWT_SECRET); }
    catch { return res.status(401).end(JSON.stringify({ error: 'invalid token' })); }

    let email =
      claims?.email ||
      claims?.user?.email ||
      claims?.data?.email ||
      '';
    email = norm(email);
    if (!email) return res.status(401).end(JSON.stringify({ error: 'no email in token' }));

    // 2) Mapping Kunde -> Rep (dfs:repOf:<email> → z.B. "rep_2")
    const repId = await upReq(`/get/${encodeURIComponent(KEY_REP_OF(email))}`);
    if (!repId) return res.status(204).end(); // keine Zuordnung

    // 3) Rep-Stammdaten laden
    const rep = await loadRepById(repId);
    if (!rep || rep.active === false) return res.status(204).end();

    // 4) Antwort normalisieren
    return res.status(200).end(JSON.stringify({
      id:       String(rep.id || repId),
      firstName:S(rep.firstName || rep.firstname),
      lastName: S(rep.lastName  || rep.lastname),
      email:    S(rep.email),
      region:   S(rep.region),
    }));
  } catch (e) {
    console.error('[rep/of-customer]', e);
    return res.status(500).end(JSON.stringify({ error: 'internal error' }));
  }
}
