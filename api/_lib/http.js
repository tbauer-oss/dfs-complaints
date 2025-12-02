// api/_lib/http.js  (ESM, shared CORS helpers)

// --- Erlaubte Frontend-Origins ---
export const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
export const LOCAL_FE = 'http://localhost:8080';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

// --- Origin prüfen ---
export function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (origin === PROD_FE || origin === LOCAL_FE) return true;
  return PREVIEW.test(origin);
}

// --- CORS setzen (immer am Handler-Anfang aufrufen!) ---
export function setCors(req, res) {
  const origin = req.headers?.origin || '';
  const allow  = isAllowedOrigin(origin) ? origin : PROD_FE;

  // Kern
  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');

  // Vom Browser angefragte Header dynamisch spiegeln; Baseline immer erlauben
  const reqAllowed = req.headers?.['access-control-request-headers'];
  const baseline   = 'Content-Type, Authorization, X-Admin-Secret, X-Gate';
  const allowHdrs  = reqAllowed && String(reqAllowed).trim().length > 0
    ? `${baseline}, ${String(reqAllowed)}`
    : baseline;
  res.setHeader('Access-Control-Allow-Headers', allowHdrs);

  // Optional: welche Response-Header der Client lesen darf
  res.setHeader('Access-Control-Expose-Headers', 'Content-Type');

  // Preflight-Caching
  res.setHeader('Access-Control-Max-Age', '600');

  // Praktisch für viele Clients
  // (Setzen wir hier, damit auch Fehlerantworten JSON-Mime haben)
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
}

// --- Preflight komfortabel beantworten ---
export function handlePreflight(req, res) {
  setCors(req, res);
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true; // bereits beantwortet
  }
  return false;
}

// --- 200 OK (JSON) ---
export function ok(res, data) {
  // CORS sollte bereits gesetzt sein; Content-Type zur Sicherheit nochmal
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = 200;
  res.end(JSON.stringify(data ?? {}));
}

// --- Fehlerantwort ---
export function bad(res, msg = 'bad request', code = 400) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = code;
  res.end(JSON.stringify({ error: msg }));
}

// --- 405 Method Not Allowed ---
export function methodNotAllowed(res) {
  return bad(res, 'method not allowed', 405);
}

// --- 204 No Content ---
export function noContent(res) {
  res.statusCode = 204;
  res.end();
}

// --- JSON-Body robust lesen (Vercel liefert oft schon geparst) ---
export function readJson(req) {
  if (req?.body && typeof req.body === 'object') return req.body;
  try {
    const raw = req?.body ?? '{}';
    return typeof raw === 'string' ? JSON.parse(raw || '{}') : (raw ?? {});
  } catch {
    return {};
  }
}

const DEFAULT_BODY_LIMIT = Number(process.env.API_BODY_LIMIT_BYTES || 64 * 1024 * 1024);

export async function readJsonBody(req, { limitBytes = DEFAULT_BODY_LIMIT } = {}) {
  if (req?.body && typeof req.body === 'object') return req.body;
  const limit = typeof limitBytes === 'number' ? limitBytes : DEFAULT_BODY_LIMIT;
  const chunks = [];
  let total = 0;

  if (!req || typeof req[Symbol.asyncIterator] !== 'function') {
    const raw = req?.body ?? '{}';
    if (typeof raw === 'string') {
      return raw.trim() ? JSON.parse(raw) : {};
    }
    return raw ?? {};
  }

  for await (const chunk of req) {
    const buf = Buffer.isBuffer(chunk)
      ? chunk
      : Buffer.from(chunk);
    total += buf.length;
    if (limit > 0 && total > limit) {
      const err = new Error('body too large');
      err.statusCode = 413;
      throw err;
    }
    chunks.push(buf);
  }

  if (!chunks.length) return {};
  const raw = Buffer.concat(chunks, total).toString('utf8');
  if (!raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch (err) {
    const parseError = new Error('invalid json');
    parseError.cause = err;
    parseError.statusCode = 400;
    throw parseError;
  }
}
