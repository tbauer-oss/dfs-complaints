// api/_lib/http.js  (ESM, shared CORS helpers)

// --- Erlaubte Frontend-Origins ---
export const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
export const LOCAL_FE = 'http://localhost:8080';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

// Prüft, ob Origin erlaubt ist
export function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (origin === PROD_FE || origin === LOCAL_FE) return true;
  return PREVIEW.test(origin);
}

// Wählt den tatsächlich zu sendenden ACAO-Wert (bei withCredentials NIE "*")
function pickAllowOrigin(origin = '') {
  return isAllowedOrigin(origin) ? origin : PROD_FE;
}

// Setzt CORS-Header (immer am Handler-Anfang aufrufen!)
export function setCors(req, res) {
  const origin = req.headers?.origin || '';
  const allow  = pickAllowOrigin(origin);

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');

  // Standard-Header + evtl. vom Browser angefragte Header (failsafe anfügen)
  const defaultAllowed = [
    'Content-Type',
    'Authorization',
    'X-Admin-Secret',
    'X-Gate',
    'Accept',
    'X-Requested-With',
  ].join(', ');

  const reqAllowed = req.headers?.['access-control-request-headers'];
  const allowHeaders = (reqAllowed && String(reqAllowed).trim().length > 0)
    ? `${defaultAllowed}, ${reqAllowed}`
    : defaultAllowed;

  res.setHeader('Access-Control-Allow-Headers', allowHeaders);

  // Preflight cachen (10 min)
  res.setHeader('Access-Control-Max-Age', '600');

  // Manche Clients erwarten Content-Type
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// Komfort-Helfer: setzt CORS und beantwortet ggf. das Preflight
export function handlePreflight(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true; // bereits beantwortet
  }
  return false;
}

// 200 + JSON
export function ok(res, data) {
  res.statusCode = 200;
  res.end(JSON.stringify(data ?? {}));
}

// Fehlerantwort mit Code
export function bad(res, msg = 'bad request', code = 400) {
  res.statusCode = code;
  res.end(JSON.stringify({ error: msg }));
}

// 405
export function methodNotAllowed(res) {
  return bad(res, 'method not allowed', 405);
}

// 204 No Content
export function noContent(res) {
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
