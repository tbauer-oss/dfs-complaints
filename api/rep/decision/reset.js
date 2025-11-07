// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

/**
 * ---- Ultra-frühes Minimal-CORS (falls Imports fehlschlagen) ----
 * Setzt ACAO immer, damit der Browser nie ohne CORS-Header bleibt.
 * Später versuchen wir unsere echte cors.js zu laden (optional).
 */
function setCorsMinimal(req, res) {
  const PROD_FE = 'https://dfs-complaints-web.vercel.app';
  const origin = req.headers?.origin || '';
  const preview = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
  const allow =
    origin && (origin === PROD_FE || preview.test(origin) || origin.startsWith('http://localhost'))
      ? origin
      : (process.env.WEB_ORIGIN || PROD_FE);

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret, X-Debug');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// Helpers
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

export default async function handler(req, res) {
  // === 1) Immer zuerst Minimal-CORS setzen ===
  try { setCorsMinimal(req, res); } catch {}

  // === 2) Preflight sofort und sauber beenden ===
  if (req.method === 'OPTIONS') {
    // Optionales Logging
    // console.log('[reset] OPTIONS', {
    //   origin: req.headers?.origin,
    //   acrm: req.headers?.['access-control-request-method'],
    //   acah: req.headers?.['access-control-request-headers'],
    // });
    return res.status(204).end();
  }

  const reqId = rid();
  const debugQ = S(req.query?.debug) === '1';
  const debugH = S(req.headers?.['x-debug']) === '1';
  const debug = debugQ || debugH;

  // === 3) Versuche echte cors.js zu laden (nice to have) ===
  // Wenn das fehlschlägt, bleiben wir bei Minimal-CORS.
  try {
    const { setCors } = await import('../_lib/cors.js');
    try { setCors(req, res, 'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret, X-Debug'); } catch {}
  } catch (e) {
    if (debug) console.warn('[reset] cors.js import failed → fallback minimal CORS', e?.message || e);
  }

  // === 4) Nur POST erlaubt ===
  if (req.method !== 'POST') {
    const payload = { ok: false, reqId, error: 'method not allowed', method: req.method };
    return debug ? res.status(200).json(payload) : res.status(405).json({ error: 'method not allowed' });
  }

  // === 5) Auth laden (dynamisch, damit Importfehler nicht CORS killen) ===
  let getRepFromAuthHeader;
  try {
    ({ getRepFromAuthHeader } = await import('../_lib/repAuth.js'));
  } catch (e) {
    console.error('[reset] repAuth import failed:', e);
    return res.status(500).json({ error: 'repAuth import failed' });
  }

  // === 6) Upstash laden ===
  let redisGet, redisSet;
  try {
    ({ redisGet, redisSet } = await import('../_lib/upstash.js'));
  } catch (e) {
    console.error('[reset] upstash import failed:', e);
    return res.status(500).json({ error: 'upstash import failed' });
  }

  // === 7) Auth prüfen ===
  let auth = null;
  try { auth = getRepFromAuthHeader(req); } catch (e) {}
  if (!auth?.repId) {
    const payload = {
      ok: false,
      reqId,
      error: 'unauthorized',
      haveAuthHeader: !!req.headers?.authorization,
      xGate: !!req.headers?.['x-gate'],
    };
    return debug ? res.status(200).json(payload) : res.status(401).json({ error: 'unauthorized' });
  }

  // === 8) Body parsen ===
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
  if (!ticket) return res.status(400).json({ error: 'ticket required' });

  // === 9) Reset-Logik ===
  try {
    const key1 = `dfs:complaint:${ticket}`;
    const key2 = `dfs:complaints:${ticket}`;

    // laden
    let obj = await redisGet(key1);
    if (!obj) obj = await redisGet(key2);
    if (!obj) {
      const payload = { error: 'complaint not found', reqId, ticket };
      return res.status(404).json(payload);
    }

    // parse
    let c = obj;
    if (typeof c === 'string') { try { c = JSON.parse(c); } catch {} }
    if (typeof c !== 'object' || Array.isArray(c) || !c) {
      return res.status(500).json({ error: 'invalid complaint format' });
    }

    // richtige Vertretung?
    if (S(c.repId) && S(c.repId) !== S(auth.repId)) {
      return res.status(403).json({ error: 'forbidden (wrong rep)' });
    }

    // Felder entfernen
    delete c.repDecision;
    delete c.repDecisionAt;
    delete c.repDecisionBy;
    delete c.repId;
    c.updatedAt = Date.now();

    // richtigen Key wiederverwenden
    const existsKey1 = !!(await redisGet(key1));
    const saveKey = existsKey1 ? key1 : key2;
    await redisSet(saveKey, JSON.stringify(c));

    // Audit (optional)
    try {
      await redisSet(
        `dfs:audit:repDecisionReset:${ticket}:${nowIso()}`,
        JSON.stringify({ by: auth.repId, at: nowIso(), action: 'reset' }),
        60 * 60 * 24 * 7
      );
    } catch (e) {
      if (debug) console.warn('[reset] audit write failed:', e?.message || e);
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
    console.error(`[reset] ${reqId} error:`, e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
}
