// api/_lib/http.js  (ESM, shared CORS helpers)

// --- Whitelist ---
export const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
export const LOCAL_FE = 'http://localhost:8080';

// Preview: beliebig viele Suffix-Blöcke
const PREVIEW = /^https:\/\/(?:dfs-complaints|dfs-complaints-web|dfs-customer-complaint)(?:-[a-z0-9-]+)*\.vercel\.app$/i;

export function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (origin === PROD_FE || origin === LOCAL_FE) return true;
  return PREVIEW.test(origin);
}

// Wähle ACAO-Wert: wenn erlaubt -> Origin, sonst PROD_FE (nie "*" bei Credentials)
function pickAllowOrigin(origin = '') {
  if (isAllowedOrigin(origin)) return origin;
  // Falls der Browser aus irgendeinem Grund kein Origin mitsendet,
  // geben wir das PROD_FE zurück, damit ACAO nie fehlt.
  return PROD_FE;
}

// Setzt CORS-Header (immer am Handler-Anfang aufrufen!)
export function setCors(req, res) {
  const origin = req?.headers?.origin || '';
  const allow  = pickAllowOrigin(origin);

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');

  // Wir sind ohne Cookies unterwegs, aber schadet nicht wenn gesetzt:
  res.setHeader('Access-Control-Allow-Credentials', 'true');

  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');

  // Erlaube wichtige Header in Groß- UND Kleinschreibung
  const baseAllowed = [
    'Content-Type', 'content-type',
    'Authorization', 'authorization',
    'X-Admin-Secret', 'x-admin-secret',
    'X-Gate', 'x-gate',
    'Accept', 'accept',
    'X-Requested-With', 'x-requested-with',
  ].join(', ');

  // Falls der Browser per Preflight zusätzliche Header anfragt, spiegeln wir sie
  const reqAllowed = req?.headers?.['access-control-request-headers'];
  const allowHeaders = (reqAllowed && String(reqAllowed).trim())
    ? `${baseAllowed}, ${reqAllowed}`
    : baseAllowed;

  res.setHeader('Access-Control-Allow-Headers', allowHeaders);

  // Preflight Cache
  res.setHeader('Access-Control-Max-Age', '600');

  // Nützlich für einige Clients
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
  // Safety: CORS auch bei späten Antworten sicherstellen
  try { setCors(res?.req || {}, res); } catch {}
  res.statusCode = 200;
  res.end(JSON.stringify(data ?? {}));
}

// Fehlerantwort mit Code
export function bad(res, msg = 'bad request', code = 400) {
  try { setCors(res?.req || {}, res); } catch {}
  res.statusCode = code;
  res.end(JSON.stringify({ error: msg }));
}

// 405
export function methodNotAllowed(res) {
  return bad(res, 'method not allowed', 405);
}

// 204 No Content
export function noContent(res) {
  try { setCors(res?.req || {}, res); } catch {}
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
