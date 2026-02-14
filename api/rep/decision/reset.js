// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors } from '../../_lib/http.js';
import { redis } from '../../_lib/redis.js';

// --- Utils ---
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

// --- Store facade ---
async function loadUpstashFacade() {
  return {
    get: async (key) => redis.get(key),
    set: async (key, value, ttlSec) => redis.set(key, value, ttlSec ? { ex: ttlSec } : undefined),
    _exports: ['redisCompat'],
  };
}

// --- repAuth laden ---
async function loadRepAuth() {
  const mod = await import(new URL('../../_lib/repAuth.js', import.meta.url));
  if (typeof mod.getRepFromAuthHeader !== 'function') {
    throw new Error('repAuth export missing');
  }
  return mod.getRepFromAuthHeader;
}

// --- Handler ---
export default async function handler(req, res) {
  // 1) CORS zuerst
  if (handlePreflight(req, res)) return;
  setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');

  const debug = S(req.query?.debug) === '1' || S(req.headers?.['x-debug']) === '1';
  const reqId = rid();

  // 3) Nur POST
  if (req.method !== 'POST') {
    return debug
      ? res.status(200).json({ ok: false, reqId, error: 'method not allowed', method: req.method })
      : res.status(405).json({ error: 'method not allowed' });
  }

  // 4) repAuth
  let getRepFromAuthHeader;
  try {
    getRepFromAuthHeader = await loadRepAuth();
  } catch (e) {
    console.error('[rep/decision/reset] repAuth load error:', e);
    return debug
      ? res.status(500).json({ ok: false, reqId, error: 'repAuth import failed' })
      : res.status(500).json({ error: 'repAuth import failed' });
  }

  // 5) Upstash-Facade
  let up;
  try {
    up = await loadUpstashFacade();
  } catch (e) {
    console.error('[rep/decision/reset] upstash load error:', e);
    return res.status(500).json({ error: 'upstash import failed' });
  }

  // 6) Auth
  let auth = null;
  try {
    auth = getRepFromAuthHeader(req);
  } catch (e) {
    console.error('[rep/decision/reset] getRepFromAuthHeader error:', e);
  }
  if (!auth?.repId) {
    return debug
      ? res.status(200).json({
          ok: false,
          reqId,
          error: 'unauthorized',
          haveAuthHeader: !!req.headers?.authorization,
          xGate: !!req.headers?.['x-gate'],
        })
      : res.status(401).json({ error: 'unauthorized' });
  }

  // 7) Body
  let ticket = '';
  let raw = '';
  try {
    if (req.body && typeof req.body === 'object') {
      ticket = S(req.body.ticket);
    } else {
      raw = S(req.body);
      ticket = S(raw ? JSON.parse(raw).ticket : '');
    }
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} invalid json:`, e, 'body=', raw);
    return res.status(400).json({ error: 'invalid json' });
  }
  if (!ticket) return res.status(400).json({ error: 'ticket required' });

  // 8) Reset-Logik
  try {
    const key1 = `dfs:complaint:${ticket}`;   // neu
    const key2 = `dfs:complaints:${ticket}`;  // alt

    let obj = await up.get(key1);
    if (!obj) obj = await up.get(key2);

    if (!obj) {
      return debug
        ? res.status(200).json({
            ok: false,
            reqId,
            error: 'complaint not found',
            ticket,
            upstashExports: up._exports,
          })
        : res.status(404).json({ error: 'complaint not found' });
    }

    let c = obj;
    if (typeof c === 'string') {
      try { c = JSON.parse(c); } catch {}
    }
    if (typeof c !== 'object' || Array.isArray(c)) {
      return res.status(500).json({ error: 'invalid complaint format' });
    }

    // Nur eigener Rep darf zurücknehmen (wenn im Datensatz repId existiert)
    if (S(c.repId) && S(c.repId) !== S(auth.repId)) {
      return debug
        ? res.status(200).json({
            ok: false,
            reqId,
            error: 'forbidden (wrong rep)',
            repIdOnRecord: c.repId,
          })
        : res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // Felder entfernen
    delete c.repDecision;
    delete c.repDecisionAt;
    delete c.repDecisionBy;
    delete c.repId;

    c.updatedAt = Date.now();

    // Speichern unter dem vorhandenen Key
    const existedInKey1 = !!(await up.get(key1));
    const saveKey = existedInKey1 ? key1 : key2;
    await up.set(saveKey, JSON.stringify(c));

    // Audit (Best-Effort, TTL 7 Tage)
    try {
      await up.set(
        `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
        JSON.stringify({ by: auth.repId, at: nowIso(), action: 'reset' }),
        60 * 60 * 24 * 7
      );
    } catch (e) {
      console.warn('[rep/decision/reset] audit write failed:', e);
    }

    return debug
      ? res.status(200).json({
          ok: true,
          reqId,
          ticket,
          removed: ['repDecision', 'repDecisionAt', 'repDecisionBy', 'repId'],
          savedKey: saveKey,
          upstashExports: up._exports,
        })
      : res.status(204).end();
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} error:`, e);
    return res.status(500).json({ error: e?.message || String(e) });
  }
}
