// api/rep/decision/reset.js
export const config = { runtime: 'nodejs' };

// --- Utils ---
const S = (v) => (v ?? '').toString().trim();
const nowIso = () => new Date().toISOString();
const rid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

// --- Fallback-CORS (falls _lib/cors.js nicht ladbar) ---
function setCorsFallback(
  req,
  res,
  allowHeaders = 'Content-Type, Authorization, X-Admin-Secret, X-Gate, X-Rep-Secret, X-Debug'
) {
  const PROD_FE = 'https://dfs-complaints-web.vercel.app';
  const origin = req.headers?.origin || '';
  const isPreview = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i.test(origin);
  const isLocal = origin.startsWith('http://localhost');

  const allow =
    origin && (origin === PROD_FE || isPreview || isLocal)
      ? origin
      : (process.env.WEB_ORIGIN || PROD_FE);

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', allowHeaders);
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

async function ensureCors(req, res, allowHeaders) {
  try {
    const mod = await import(new URL('../../_lib/cors.js', import.meta.url));
    if (typeof mod.setCors === 'function') {
      mod.setCors(req, res, allowHeaders);
      return;
    }
    setCorsFallback(req, res, allowHeaders);
  } catch {
    setCorsFallback(req, res, allowHeaders);
  }
}

// --- Upstash-Facade: passt sich an eure Exporte an; mit lokalem Fallback ---
async function loadUpstashFacade() {
  // 1) Versuche eure _lib/upstash.js zu laden
  let exp = {};
  try {
    const mod = await import(new URL('../../_lib/upstash.js', import.meta.url));
    exp = mod || {};
  } catch {
    // ignorieren – wir versuchen Fallback
  }

  // 2) Kandidaten aus eurer Facade
  let get =
    exp.redisGet ??
    exp.get ??
    exp.redisGetJSON ??
    null;

  let set = null;

  // 3) Falls noch kein set/get: lokaler Upstash-Client per ENV aufbauen
  const url =
    process.env.REDIS_URL ||
    process.env.UPSTASH_REDIS_REST_URL ||
    '';
  const token =
    process.env.REDIS_TOKEN ||
    process.env.UPSTASH_REDIS_REST_TOKEN ||
    '';

  let client = null;
  if ((!get || !set) && url && token) {
    try {
      const { Redis } = await import('@upstash/redis');
      client = new Redis({ url, token });
    } catch {
      // kein Client verfügbar – dann bleiben wir ohne Fallback
    }
  }

  // 4) Falls get noch fehlt, nutze Client.get
  if (!get && client) {
    get = async (key) => client.get(key);
  } else if (!get && typeof exp.redisMGet === 'function') {
    // ursprünglicher MGET-Fallback
    get = async (key) => {
      const arr = await exp.redisMGet([key]);
      return Array.isArray(arr) ? (arr[0] ?? null) : null;
    };
  }

  // 5) set-Kandidatenauswahl (inkl. Client-Fallback)
  if (typeof exp.redisSet === 'function') {
    set = (key, value, ttlSec) => exp.redisSet(key, value, ttlSec);
  } else if (typeof exp.set === 'function') {
    set = (key, value, ttlSec) => {
      const opts = ttlSec ? { ex: ttlSec } : undefined;
      return exp.set(key, value, opts);
    };
  } else if (typeof exp.redisSetEx === 'function') {
    set = (key, value, ttlSec) => exp.redisSetEx(key, value, ttlSec || 0);
  } else if (typeof exp.redisSetJSON === 'function') {
    set = (key, value, ttlSec) => exp.redisSetJSON(key, value, ttlSec);
  } else if (client) {
    // lokaler Fallback
    set = (key, value, ttlSec) => {
      const opts = ttlSec ? { ex: ttlSec } : undefined;
      return client.set(key, value, opts);
    };
  }

  if (!get) throw new Error('No redis get function available');
  if (!set) throw new Error('No redis set function available');

  return {
    get,
    set,
    _exports: Object.keys(exp),
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
  await ensureCors(req, res, 'Content-Type, Authorization, X-Gate, X-Debug');

  // 2) Preflight
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

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

    // Audit – Variante B: EIN Key pro Ticket mit Liste von Resets, TTL 7 Tage
    try {
      const auditKey = `dfs:audit:repDecisionReset:${ticket}`;
      const prev = await up.get(auditKey);
      let list = [];

      if (Array.isArray(prev)) {
        list = prev;
      } else if (typeof prev === 'string' && prev.trim()) {
        try {
          const parsed = JSON.parse(prev);
          if (Array.isArray(parsed)) list = parsed;
        } catch {
          // wenn kein gültiges JSON: neu anfangen
          list = [];
        }
      }

      list.push({
        by: auth.repId,
        at: nowIso(),
        action: 'reset',
        reqId,
      });

      await up.set(auditKey, JSON.stringify(list), 60 * 60 * 24 * 7); // 7 Tage TTL
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
