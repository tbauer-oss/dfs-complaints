// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../../_lib/cors.js';
import { getRepFromAuthHeader } from '../../_lib/repAuth.js';
import { redisGet, redisSet, redisHGet, redisHSet, redisDel, redisHDel } from '../../_lib/upstash.js';

function S(v) { return (v ?? '').toString().trim(); }

export default async function handler(req, res) {
  // --- CORS IMMER ZUERST ---
  setCors(req, res, 'Content-Type, Authorization, X-Gate');
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'POST') {
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  // --- Auth: Vertreter ermitteln ---
  let auth = null;
  try { auth = getRepFromAuthHeader(req); } catch (e) {}
  if (!auth?.repId) {
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  // --- Payload ---
  let ticket = '';
  try {
    const j = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    ticket = S(j.ticket);
  } catch {}
  if (!ticket) {
    return res.status(400).end(JSON.stringify({ error: 'missing ticket' }));
  }

  // --- Reset-Logik: defensiv beide Varianten abräumen ---
  try {
    // a) einfacher Key (falls du repDecision separat speicherst)
    await redisDel(`dfs:repDecision:${ticket}`);

    // b) Feld in Complaint-Hash (häufiger)
    await redisHDel(`dfs:complaint:${ticket}`, 'repDecision');

    // c) optional: Zeitstempel/Bemerkungen zurücksetzen (keine Pflicht)
    await redisHDel(`dfs:complaint:${ticket}`, 'repDecisionAt');
    await redisHDel(`dfs:complaint:${ticket}`, 'repDecisionNote');
  } catch (e) {
    console.error('[rep/decision/reset] error:', e);
    // Wir antworten trotzdem normschön, aber mit 200 + Fehlertext wäre auch OK.
    // Für Preflight/CORS ist wichtig, dass die Route nie vor setCors crasht.
  }

  // Kein Body nötig → 204
  return res.status(204).end();
}
