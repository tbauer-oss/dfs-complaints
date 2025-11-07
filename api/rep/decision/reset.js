// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

// ---------- kleine Utils ----------
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

// Fallback-CORS (falls _lib/cors.js nicht importierbar ist)
function setCorsFallback(req, res, allowHeaders =
  'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret, X-Debug'
) {
  const PROD_FE = 'https://dfs-complaints-web.vercel.app';
  const origin = req.headers?.origin || '';
  const isPreview = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i.test(origin);
  const isLocal = origin.startsWith('http://localhost');
  const allow = origin && (origin === PROD_FE || isPreview || isLocal)
    ? origin
    : (process.env.WEB_ORIGIN || PROD_FE);

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', allowHeaders);
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// Lazy-Loader für setCors (mit Fallback)
async function ensureCors(req, res, allowHeaders) {
  try {
    // Normpfad: Datei liegt unter api/_lib/cors.js
    const mod = await import('../_lib/cors.js');
    if (typeof mod.setCors === 'function') {
      mod.setCors(req, res, allowHeaders);
      return 'lib';
    }
    // falls kein Export -> Fallback
    setCorsFallback(req, res, allowHeaders);
    return 'fallback-noexport';
  } catch (_) {
    // Pfadproblem? Fallback nutzen
    setCorsFallback(req, res, allowHeaders);
    return 'fallback-import-failed';
  }
}

// Lazy-Loader für repAuth (robust, 2 Pfade)
async function loadRepAuth(debug = false) {
  let mod = null, e1 = null, e2 = null;
  try { mod = await import('../_lib/repAuth.js'); } catch (e) { e1 = e; }
  if (!mod) { try { mod = await import('../_lib/repAuth.js'); } catch (e) { e2 = e; } }
  if (!mod || typeof mod.getRepFromAuthHeader !== 'function') {
    const err = new Error('repAuth import failed');
    if (debug) err.details = {
      e1: e1 ? (e1.message || String(e1)) : null,
      e2: e2 ? (e2.message || String(e2)) : null,
      moduleKeys: mod ? Object.keys(mod) : [],
    };
    throw err;
  }
  return mod.getRepFromAuthHeader;
}

// Lazy-Loader für Upstash-Helpers (nur ein Pfad nötig)
async function loadUpstash() {
  const mod = await import('../_lib/upstash.js');
  return { redisGet: mod.redisGet, redisSet: mod.redisSet };
}

// ---------- Handler ----------
export default async function handler(req, res) {
  // ==== CORS IMMER ZUERST (mit garantiertem Fallback) ====
  await ensureCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');

  // ==== Preflight ====
  if (req.method === 'OPTIONS') {
    // Wichtig: 204 ohne Body – Header sind bereits gesetzt.
    return res.status(204).end();
  }

  const debug = S(req.query?.debug) === '1' || S(req.headers?.['x-debug']) === '1';
  const reqId = rid();

  // ==== Nur POST ====
  if (req.method !== 'POST') {
    return debug
      ? res.status(200).json({ ok: false, reqId, error: 'method not allowed', method: req.method })
      : res.status(405).json({ error: 'method not allowed' });
  }

  // ==== repAuth laden ====
  let getRepFromAuthHeader;
  try {
    getRepFromAuthHeader = await loadRepAuth(debug);
  } catch (e) {
    console.error('[rep/decision/reset] repAuth load error:', e);
    return debug
      ? res.status(500).json({ ok: false, reqId, error: 'repAuth import failed', details: e.details || (e.message || String(e)) })
      : res.status(500).json({ error: 'repAuth import failed' });
  }

  // ==== Upstash laden ====
  let redisGet, redisSet;
  try {
    ({ redisGet, redisSet } = await loadUpstash());
  } catch (e) {
    console.error('[rep/decision/reset] upstash load error:', e);
    return res.status(500).json({ error: 'upstash import failed' });
  }

  // ==== Auth ====
  let auth = null;
  try {
    auth = getRepFromAuthHeader(req);
  } catch (e) {
    console.error('[rep/decision/reset] getRepFromAuthHeader error:', e);
  }
  if (!auth?.repId) {
    return debug
      ? res.status(200).json({
          ok: false, reqId, error: 'unauthorized',
          haveAuthHeader: !!req.headers?.authorization,
          xGate: !!req.headers?.['x-gate'],
        })
      : res.status(401).json({ error: 'unauthorized' });
  }

  // ==== Body ====
  let ticket = '';
  let bodyRaw = '';
  try {
    if (req.body && typeof req.body === 'object') {
      ticket = S(req.body.ticket);
    } else {
      bodyRaw = S(req.body);
      const j = bodyRaw ? JSON.parse(bodyRaw) : {};
      ticket = S(j.ticket);
    }
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} invalid json:`, e, 'body=', bodyRaw);
    return res.status(400).json({ error: 'invalid json' });
  }
  if (!ticket) {
    return res.status(400).json({ error: 'ticket required' });
  }

  // ==== Reset-Logik ====
  try {
    const key1 = `dfs:complaint:${ticket}`;
    const key2 = `dfs:complaints:${ticket}`;
    let obj = await redisGet(key1);
    if (!obj) obj = await redisGet(key2);

    if (!obj) {
      return debug
        ? res.status(200).json({ ok: false, reqId, error: 'complaint not found', ticket })
        : res.status(404).json({ error: 'complaint not found' });
    }

    let c = obj;
    if (typeof c === 'string') {
      try { c = JSON.parse(c); } catch {}
    }
    if (typeof c !== 'object' || Array.isArray(c)) {
      return res.status(500).json({ error: 'invalid complaint format' });
    }

    // Vertreter darf nur eigene Entscheidung zurücknehmen
    if (S(c.repId) && S(c.repId) !== S(auth.repId)) {
      return debug
        ? res.status(200).json({ ok: false, reqId, error: 'forbidden (wrong rep)', ticket, repIdOnRecord: c.repId })
        : res.status(403).json({ error: 'forbidden (wrong rep)' });
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

    // Audit (Best-Effort)
    try {
      await redisSet(
        `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
        JSON.stringify({ by: auth.repId, at: nowIso(), action: 'reset' }),
        60 * 60 * 24 * 7
      );
    } catch (e) {
      console.warn('[rep/decision/reset] audit write failed:', e);
    }

    return debug
      ? res.status(200).json({
          ok: true, reqId, ticket,
          removed: ['repDecision', 'repDecisionAt', 'repDecisionBy', 'repId'],
          savedKey,
        })
      : res.status(204).end();
  } catch (e) {
    console.error(`[rep/decision/reset] ${reqId} error:`, e);
    return res.status(500).json({ error: e?.message || String(e) });
  }
}
