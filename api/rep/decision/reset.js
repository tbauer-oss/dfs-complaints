// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

import { setCors } from '../../_lib/cors.js';
import { getRepFromAuthHeader } from '../../_lib/repAuth.js';
import { redisHDel, redisSet } from '../../_lib/upstash.js'; // HDel & optional Audit

// -------- Utils --------
const S = v => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

/**
 * Sichert, dass CORS *immer* gesetzt ist – auch bei Fehlern.
 * Gibt optional eine Debug-Antwort (JSON 200) statt 204 zurück.
 */
export default async function handler(req, res) {
  // ==== CORS IMMER ZUERST ====
  try {
    // erlaube genau die Header, die du im Preflight anfragst
    setCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug, X-Dry');
  } catch (e) {
    // selbst wenn setCors hier scheitern würde, loggen:
    console.error('[reset] setCors failed:', e);
  }

  // ===== Preflight =====
  if (req.method === 'OPTIONS') {
    console.log('[reset] OPTIONS preflight', {
      origin: req.headers?.origin,
      acrm: req.headers?.['access-control-request-method'],
      acah: req.headers?.['access-control-request-headers'],
    });
    return res.status(204).end();
  }

  const debug = (S(req.query?.debug) === '1') || (S(req.headers['x-debug']) === '1');
  const dry   = (S(req.query?.dry) === '1')   || (S(req.headers['x-dry']) === '1');
  const reqId = rid();

  // Nur POST (außer explizitem Debug-GET)
  if (req.method !== 'POST' && !(debug && req.method === 'GET')) {
    if (debug) {
      return res.status(200).end(JSON.stringify({
        ok: false,
        reqId,
        error: 'method not allowed',
        method: req.method,
        hint: 'Use POST (or GET?debug=1 for debug ping).',
      }));
    }
    return res.status(405).end(JSON.stringify({ error: 'method not allowed' }));
  }

  // ===== Auth (Vertreter) =====
  let auth = null;
  try {
    auth = getRepFromAuthHeader(req);
  } catch (e) {
    console.error('[reset] getRepFromAuthHeader threw:', e);
  }
  if (!auth?.repId) {
    if (debug) {
      return res.status(200).end(JSON.stringify({
        ok: false,
        reqId,
        error: 'unauthorized',
        haveAuthHeader: !!req.headers?.authorization,
        gate: !!req.headers?.['x-gate'],
      }));
    }
    return res.status(401).end(JSON.stringify({ error: 'unauthorized' }));
  }

  // ===== Body parsen (bei GET?debug=1 erlauben wir ticket im Query) =====
  let ticket = '';
  let bodyRaw = '';

  try {
    if (req.method === 'GET') {
      ticket = S(req.query?.ticket);
    } else {
      if (typeof req.body === 'object' && req.body !== null) {
        ticket = S(req.body.ticket);
        bodyRaw = '[object]'; // nicht loggen
      } else {
        bodyRaw = S(req.body);
        const j = bodyRaw ? JSON.parse(bodyRaw) : {};
        ticket = S(j.ticket);
      }
    }
  } catch (e) {
    const msg = 'invalid json';
    console.error(`[reset] ${reqId} JSON parse failed:`, e, 'raw=', bodyRaw?.slice(0, 200));
    if (debug) {
      return res.status(200).end(JSON.stringify({
        ok: false,
        reqId,
        error: msg,
        bodyPreview: bodyRaw?.slice(0, 200),
      }));
    }
    return res.status(400).end(JSON.stringify({ error: msg }));
  }

  if (!ticket) {
    if (debug) {
      return res.status(200).end(JSON.stringify({
        ok: false,
        reqId,
        error: 'ticket required',
      }));
    }
    return res.status(400).end(JSON.stringify({ error: 'ticket required' }));
  }

  // ===== Debug-Header ins Log (hilft bei CORS-Diagnose) =====
  console.log('[reset] incoming', {
    reqId,
    method: req.method,
    url: req.url,
    origin: req.headers?.origin,
    host: req.headers?.host,
    acrm: req.headers?.['access-control-request-method'],
    acah: req.headers?.['access-control-request-headers'],
    contentType: req.headers?.['content-type'],
    authHeader: !!req.headers?.authorization,
    xGate: !!req.headers?.['x-gate'],
    debug,
    dry,
    ticket,
    repId: auth.repId,
  });

  // ===== Reset-Logik =====
  try {
    const redisKey = `dfs:complaint:${ticket}`;

    if (!dry) {
      await redisHDel(redisKey, 'repDecision'); // eigentlicher Reset
      // optionale Auditspur, Best-Effort
      try {
        await redisSet(
          `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
          JSON.stringify({ by: auth.repId, at: nowIso(), action: 'reset' }),
          60 * 60 * 24 * 7 // 7 Tage
        );
      } catch (e) {
        console.warn('[reset] audit write failed:', e);
      }
    }

    if (debug) {
      return res.status(200).end(JSON.stringify({
        ok: true,
        reqId,
        ticket,
        didWrite: !dry,
        message: dry ? 'DRY-RUN: would reset repDecision' : 'repDecision cleared',
      }));
    }

    // normale Produktion: 204 ohne Body
    return res.status(204).end();
  } catch (e) {
    console.error(`[reset] ${reqId} internal error:`, e);
    if (debug) {
      return res.status(200).end(JSON.stringify({
        ok: false,
        reqId,
        error: 'internal error',
        message: S(e?.message) || S(e),
      }));
    }
    return res.status(500).end(JSON.stringify({ error: 'internal error' }));
  }
}
