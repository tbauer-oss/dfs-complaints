// api/_lib/http.js  (ESM, shared CORS helpers)

// --- HARTE Whitelist ---
export const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
export const LOCAL_FE = 'http://localhost:8080';

// Breite Preview-RegEx: beliebig viele Suffix-Blöcke
export const PREVIEW = /^https:\/\/(?:dfs-complaints|dfs-complaints-web|dfs-customer-complaint)(?:-[a-z0-9-]+)*\.vercel\.app$/i;

// Prüft, ob Origin erlaubt ist
export function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (origin === PROD_FE || origin === LOCAL_FE) return true;
  return PREVIEW.test(origin);
}

// Setzt CORS-Header (immer am Handler-Anfang aufrufen!)
export function setCors(req, res) {
  const origin = req?.headers?.origin || '';
  const allowed = isAllowedOrigin(origin);

  if (allowed) {
    // Für Prod/Preview/Local: Origin spiegeln + Credentials zulassen
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Credentials', 'true');
  } else {
    // Fallback für unbekannte Origins (z. B. externe Tools)
    res.setHeader('Access-Control-Allow-Origin', '*');
    // KEIN Allow-Credentials setzen!
  }

  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');

  const defaultAllowed = [
    'Content-Type',
    'Authorization',
    'X-Admin-Secret',
    'X-Gate',
    'Accept',
    'X-Requested-With',
  ];

  // dynamisch vom Browser angefragte Header (Preflight) robust anhängen
  const reqAllowed = String(req?.headers?.['access-control-request-headers'] || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

  // Merge & dedupe
  const allowHeaders = Array.from(new Set([...defaultAllowed, ...reqAllowed])).join(', ');
  res.setHeader('Access-Control-Allow-Headers', allowHeaders);

  // Optional hilfreich für Clients, die Response-Header lesen möchten
  res.setHeader('Access-Control-Expose-Headers', 'Content-Type');

  // Preflight cachen (10 min)
  res.setHeader('Access-Control-Max-Age', '600');

  // Manche Clients erwarten Content-Type
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// Beantworte OPTIONS zuverlässig
export function handlePreflight(req, res) {
  setCors(req, res);
  if (req?.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  return false;
}

// 200 + JSON
export function ok(res, data) {
  setCors(reqFromRes(res), res); // safety: auch bei späteren Antworten CORS sicherstellen
  res.statusCode = 200;
  res.end(JSON.stringify(data ?? {}));
}

// Fehlerantwort mit Code
export function bad(res, msg = 'bad request', code = 400) {
  setCors(reqFromRes(res), res);
  res.statusCode = code;
  res.end(JSON.stringify({ error: msg }));
}

// 405
export function methodNotAllowed(res) {
  return bad(res, 'method not allowed', 405);
}

// 204 No Content
export function noContent(res) {
  setCors(reqFromRes(res), res);
  res.statusCode = 204;
  res.end();
}

// JSON-Body robust lesen
export function readJson(req) {
  if (req?.body && typeof req.body === 'object') return req.body;
  try {
    return JSON.parse(req?.body ?? '{}');
  } catch {
    return {};
  }
}

// --- Hilfsfunktion, um in ok/bad/noContent nochmal an req zu kommen ---
function reqFromRes(res) {
  // Vercel/Node hängt das ursprüngliche req je nach Laufzeit an unterschiedliche Stellen
  // @ts-ignore
  return (
    res?.req ||
    // Node <-> Vercel Parser
    res?.socket?.parser?.incoming ||
    // Edge/Next Compat (falls vorhanden)
    res?.socket?.server?.request ||
    {}
  );
}
