export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { redisGet, redisSet, redisHGetAll, redisHSet } from '../_lib/upstash.js';

function S(v) { return (v ?? '').toString().trim(); }
const COMPLAINT_KEY = (t) => `dfs:complaint:${t}`;

/**
 * Setzt die Vertreter-Entscheidung für ein Ticket zurück:
 * - JSON-Value (String) → repDecision = '' und repDecisionAt entfernen
 * - Hash → Feld "repDecision" = ''
 */
async function clearRepDecision(ticket) {
  const key = COMPLAINT_KEY(ticket);

  // 1) Versuch: JSON-Blob
  const raw = await redisGet(key);
  if (raw) {
    try {
      const obj = JSON.parse(raw);
      obj.repDecision = '';
      if ('repDecisionAt' in obj) delete obj.repDecisionAt;
      await redisSet(key, JSON.stringify(obj));
      return true;
    } catch {
      // nicht-JSON → weiter unten Hash versuchen
    }
  }

  // 2) Versuch: Hash
  const hash = await redisHGetAll(key); // erwartet Objekt oder null
  if (hash && typeof hash === 'object') {
    await redisHSet(key, { repDecision: '' });
    return true;
  }

  // 3) Nichts gefunden
  const err = new Error('not found');
  err.status = 404;
  throw err;
}

export default async function handler(req, res) {
  // --- CORS immer zuerst ---
  setCors(req, res, 'Content-Type, Authorization, X-Admin-Secret, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'POST') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  // --- Auth: Vertreter prüfen ---
  let auth = null;
  try { auth = getRepFromAuthHeader(req); } catch (e) {}
  if (!auth?.repId) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  // --- Body lesen (JSON oder bereits geparst) ---
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  } else if (!body || typeof body !== 'object') {
    body = {};
  }

  const ticket = S(body.ticket);
  if (!ticket) {
    return res.status(400).end(JSON.stringify({ error: 'ticket required' }));
  }

  try {
    await clearRepDecision(ticket);
    return res.status(204).end(); // No Content
  } catch (e) {
    const sc = e?.status || 500;
    return res.status(sc).end(JSON.stringify({ error: S(e.message) || 'internal error' }));
  }
}
