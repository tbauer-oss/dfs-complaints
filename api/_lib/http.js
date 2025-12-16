// api/_lib/http.js  (ESM, shared CORS helpers)

// --- Erlaubte Frontend-Origins ---
export const PROD_FE   = 'https://dfs-complaints-web.vercel.app';
export const ADMIN_FE  = process.env.ADMIN_ORIGIN  || 'https://dfs-complaints-admin.vercel.app';
export const PORTAL_FE = process.env.PORTAL_ORIGIN || 'https://dfs-complaints.vercel.app';
export const LOCAL_FE  = 'http://localhost:8080';
const PREVIEW_WEB    = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
const PREVIEW_ADMIN  = /^https:\/\/dfs-complaints-admin-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
const PREVIEW_PORTAL = /^https:\/\/dfs-complaints-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

const LOCAL_PATTERN = /^http:\/\/localhost(?::\d+)?$/i;

function extraOrigins() {
  return (process.env.CORS_EXTRA_ORIGINS || '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
}

// --- Origin prüfen ---
export function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (
    origin === PROD_FE ||
    origin === ADMIN_FE ||
    origin === PORTAL_FE ||
    origin === LOCAL_FE ||
    LOCAL_PATTERN.test(origin) ||
    PREVIEW_WEB.test(origin) ||
    PREVIEW_ADMIN.test(origin) ||
    PREVIEW_PORTAL.test(origin) ||
    extraOrigins().includes(origin)
  ) return true;
  return false;
}

// --- CORS setzen (immer am Handler-Anfang aufrufen!) ---
export function setCors(req, res, allowHeaders = '') {
  const origin = req?.headers?.origin || '';
  const allowOrigin = isAllowedOrigin(origin) ? origin : PROD_FE;

  const baselineHeaders = ['Content-Type', 'Authorization', 'X-Requested-With', 'X-Admin-Secret', 'X-Gate', 'X-Rep-Secret'];
  const extras = String(allowHeaders || '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean);

  const mergedHeaders = [...baselineHeaders, ...extras]
    .map((h) => h.toLowerCase())
    .filter((h, idx, arr) => arr.indexOf(h) === idx)
    .map((h) => h
      .split('-')
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join('-'))
    .join(', ');

  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', mergedHeaders);
  res.setHeader('Access-Control-Max-Age', '86400');
  res.setHeader('Access-Control-Allow-Credentials', 'true');

  res.__corsApplied = true;
  res.__corsOrigin = allowOrigin;

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

function ensureCorsHeaders(res) {
  if (res.getHeader('Access-Control-Allow-Origin')) return;
  const allowOrigin = res.__corsOrigin || PROD_FE;
  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, X-Admin-Secret, X-Gate, X-Rep-Secret');
  res.setHeader('Access-Control-Max-Age', '86400');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
}

// --- 200 OK (JSON) ---
export function ok(res, data) {
  // CORS sollte bereits gesetzt sein; Content-Type zur Sicherheit nochmal
  ensureCorsHeaders(res);
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = 200;
  res.end(JSON.stringify(data ?? {}));
}

// --- Fehlerantwort ---
export function bad(res, msg = 'bad request', code = 400, extra = undefined) {
  ensureCorsHeaders(res);
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.statusCode = code;
  const body = typeof extra === 'object' && extra !== null ? { error: msg, ...extra } : { error: msg };
  res.end(JSON.stringify(body));
}

// --- 405 Method Not Allowed ---
export function methodNotAllowed(res) {
  return bad(res, 'method not allowed', 405);
}

// --- 204 No Content ---
export function noContent(res) {
  ensureCorsHeaders(res);
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
