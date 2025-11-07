export const config = { runtime: 'nodejs' };

import { setCors } from '../../_lib/cors.js';
import { redisGet, redisSet } from '../../_lib/upstash.js';

// ---------- kleine Utils ----------
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

// Wir deklarieren die Variable hier und füllen sie nach dem Importversuch
let getRepFromAuthHeaderFn = null;

/**
 * Versuche repAuth.js defensiv über gängige Pfade zu laden.
 * Wir machen das lazy im Handler, damit Vercel / ESM keine Top-Level-Import-Probleme macht.
 */
async function loadRepAuth(debug = false) {
  if (getRepFromAuthHeaderFn) return; // schon geladen
  let mod = null;
  let error1 = null, error2 = null;

  // Pfad 1: wenn reset.js in api/rep/decision/reset.js liegt -> ../../_lib/repAuth.js
  try {
    mod = await import('../../_lib/repAuth.js');
  } catch (e) { error1 = e; }

  // Fallback Pfad 2: falls die Route woanders liegt -> ../_lib/repAuth.js
  if (!mod) {
    try {
      mod = await import('../_lib/repAuth.js');
    } catch (e) { error2 = e; }
  }

  if (!mod || (typeof mod.getRepFromAuthHeader !== 'function')) {
    // Für Debug zweckdienliche Infos zurückgeben
    const msg = 'repAuth import failed';
    if (debug) {
      const reasons = {
        error1: error1 ? (error1.message || String(error1)) : null,
        error2: error2 ? (error2.message || String(error2)) : null,
        moduleKeys: mod ? Object.keys(mod) : [],
      };
      throw Object.assign(new Error(msg), { reasons });
    }
    throw new Error(msg);
  }
  getRepFromAuthHeaderFn = mod.getRepFromAuthHeader;
}

// ---------- Handler ----------
export default async function handler(req, res) {
  // ==== CORS IMMER ZUERST ====
  try {
    setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');
  } catch (e) {
    console.error('[rep/decision/reset] setCors failed:', e);
  }

  // ==== Preflight ====
  if (req.method === 'OPTIONS') {
    // Hinweis: Browser zeigen die CORS-Header hier oft nicht im JS-Console-Log an (ist normal),
    // im Network-Tab siehst du sie.
    return res.status(204).end();
  }

  const debug =
    S(req.query?.debug) === '1' ||
    S(req.headers?.['x-debug']) === '1';

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

  // ==== repAuth laden ====
  try {
    await loadRepAuth(debug);
  } catch (e) {
    console.error('[rep/decision/reset] repAuth load error:', e);
    if (debug) {
      return res.status(500).json({
        ok: false,
        reqId,
        error: 'repAuth import failed',
        details: e.reasons || (e.message || String(e)),
      });
    }
    return res.status(500).json({ error: 'repAuth import failed' });
  }

  // ==== Auth prüfen ====
  let auth = null;
  try {
    auth = getRepFromAuthHeaderFn(req);
  } catch (e) {
    console.error('[rep/decision/reset] getRepFromAuthHeader error:', e);
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
    console.error(`[rep/decision/reset] ${reqId} JSON parse failed:`, e, 'body=', bodyRaw);
    return res.status(400).json({ error: 'invalid json' });
  }
  if (!ticket) {
    return res.status(400).json({ error: 'ticket required' });
  }

  // Logging (knapp)
  if (debug) {
    console.log('[rep/decision/reset] incoming', {
      reqId,
      ticket,
      repId: auth.repId,
      origin: req.headers?.origin,
    });
  }

  // ==== Reset-Logik ====
  try {
    const key1 = `dfs:complaint:${ticket}`;
    const key2 = `dfs:complaints:${ticket}`;
    let obj = await redisGet(key1);
    if (!obj) obj = await redisGet(key2);

    if (!obj) {
      if (debug) {
        return res.status(200).json({ ok: false, reqId, error: 'complaint not found', ticket });
      }
      return res.status(404).json({ error: 'complaint not found' });
    }

    let c = obj;
    if (typeof c === 'string') {
      try { c = JSON.parse(c); } catch {}
    }
    if (typeof c !== 'object' || Array.isArray(c)) {
      return res.status(500).json({ error: 'invalid complaint format' });
    }

    // Nur eigener Fall oder leerer repId zulässig
    if (S(c.repId) && S(c.repId) !== S(auth.repId)) {
      if (debug) {
        return res.status(200).json({ ok: false, reqId, error: 'forbidden (wrong rep)', ticket, repIdOnRecord: c.repId });
      }
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // Felder entfernen
    delete c.repDecision;
    delete c.repDecisionAt;
    delete c.repDecisionBy;
    delete c.repId;
    c.updatedAt = Date.now();

    // denselben Key wiederverwenden
    const saveKey = (await redisGet(key1)) ? key1 : key2;
    await redisSet(saveKey, JSON.stringify(c));

    // Audit (best effort)
    try {
      await redisSet(
        `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
        JSON.stringify({ by: auth.repId, at: nowIso(), action: 'reset' }),
        60 * 60 * 24 * 7
      );
    } catch (e) {
      console.warn('[rep/decision/reset] audit write failed:', e);
    }

    if (debug) {
      return res.status(200).json({
        ok: true,
        reqId,
        ticket,
        removed: ['repDecision', 'repDecisionAt', 'repDecisionBy', 'repId'],
        savedKey: saveKey,
      });
    }
    return res.status(204).end();
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} error:`, e);
    return res.status(500).json({ error: e?.message || String(e) });
  }
}
