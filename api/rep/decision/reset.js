export const config = { runtime: 'nodejs' };

import { setCors } from '../_lib/cors.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { redisGet, redisSet } from '../_lib/upstash.js';

// ---------- Helpers ----------
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

// ---------- Handler ----------
export default async function handler(req, res) {
  // ==== CORS IMMER ZUERST ====
  try {
    setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');
  } catch (e) {
    console.error('[reset] setCors failed:', e);
  }

  // ==== Preflight ====
  if (req.method === 'OPTIONS') {
    console.log('[reset] OPTIONS preflight', {
      origin: req.headers?.origin,
      acrm: req.headers?.['access-control-request-method'],
      acah: req.headers?.['access-control-request-headers'],
    });
    // wichtig: Header sind bereits gesetzt
    return res.status(204).end();
  }

  const debug = S(req.query?.debug) === '1' || S(req.headers['x-debug']) === '1';
  const reqId = rid();

  // ==== Nur POST erlaubt ====
  if (req.method !== 'POST') {
    if (debug) {
      return res.status(200).json({
        ok: false,
        reqId,
        error: 'method not allowed',
        method: req.method,
      });
    }
    return res.status(405).json({ error: 'method not allowed' });
  }

  // ==== Auth prüfen ====
  let auth = null;
  try {
    auth = getRepFromAuthHeader(req);
  } catch (e) {
    console.error('[reset] getRepFromAuthHeader failed:', e);
  }
  if (!auth?.repId) {
    if (debug) {
      return res.status(200).json({
        ok: false,
        reqId,
        error: 'unauthorized',
        haveAuthHeader: !!req.headers?.authorization,
        xGate: !!req.headers?.['x-gate'],
      });
    }
    return res.status(401).json({ error: 'unauthorized' });
  }

  // ==== Body parsen ====
  let ticket = '';
  let bodyRaw = '';
  try {
    if (typeof req.body === 'object' && req.body !== null) {
      ticket = S(req.body.ticket);
    } else {
      bodyRaw = S(req.body);
      const j = bodyRaw ? JSON.parse(bodyRaw) : {};
      ticket = S(j.ticket);
    }
  } catch (e) {
    console.error(`[reset] ${reqId} JSON parse failed:`, e, 'body=', bodyRaw);
    return res.status(400).json({ error: 'invalid json' });
  }

  if (!ticket) {
    return res.status(400).json({ error: 'ticket required' });
  }

  console.log('[reset] incoming', {
    reqId,
    method: req.method,
    origin: req.headers?.origin,
    ticket,
    repId: auth.repId,
  });

  // ==== Reset-Logik ====
  try {
    const key1 = `dfs:complaint:${ticket}`;
    const key2 = `dfs:complaints:${ticket}`;

    // 1) Complaint aus Redis laden (plural/singular)
    let obj = await redisGet(key1);
    if (!obj) obj = await redisGet(key2);

    if (!obj) {
      console.warn(`[reset] ${reqId} complaint not found for ${ticket}`);
      return res.status(404).json({ error: 'complaint not found' });
    }

    let c = obj;
    if (typeof c === 'string') {
      try { c = JSON.parse(c); } catch {}
    }

    if (typeof c !== 'object' || Array.isArray(c)) {
      return res.status(500).json({ error: 'invalid complaint format' });
    }

    // 2) Prüfen, ob dieser Vertreter dazu gehört
    if (S(c.repId) && S(c.repId) !== S(auth.repId)) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // 3) Entferne alle repDecision-Felder
    const removed = [];
    ['repDecision', 'repDecisionAt', 'repDecisionBy', 'repId'].forEach(k => {
      if (k in c) {
        delete c[k];
        removed.push(k);
      }
    });

    // 4) Aktualisiere updatedAt
    c.updatedAt = Date.now();

    // 5) In Redis zurückschreiben (gleicher Key wie geladen)
    const saveKey = (await redisGet(key1)) ? key1 : key2;
    await redisSet(saveKey, JSON.stringify(c));

    // 6) Optional: Audit-Log
    try {
      await redisSet(
        `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
        JSON.stringify({ by: auth.repId, at: nowIso(), action: 'reset' }),
        60 * 60 * 24 * 7 // 7 Tage
      );
    } catch (e) {
      console.warn('[reset] audit write failed:', e);
    }

    // 7) Debug-Ausgabe oder leere 204-Antwort
    if (debug) {
      return res.status(200).json({
        ok: true,
        reqId,
        ticket,
        removed,
        savedKey: saveKey,
      });
    }

    // Erfolg ohne Body
    return res.status(204).end();
  } catch (e) {
    console.error(`[reset] ${reqId} error:`, e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
