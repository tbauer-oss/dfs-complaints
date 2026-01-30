// api/_lib/http.js  (ESM, shared CORS helpers)

// --- Erlaubte Frontend-Origins ---
export const PROD_FE = 'https://dfs-complaints-web.vercel.app';
const ALLOWED_ORIGINS = new Set([PROD_FE, 'http://localhost:3000', 'http://localhost:5173']);

const ALLOWED_METHODS = 'GET,POST,PUT,PATCH,DELETE,OPTIONS';
const ALLOWED_HEADERS = 'Authorization, Content-Type, X-Requested-With';
const MAX_AGE = '86400';

function readOriginHeader(req) {
  if (!req) return '';
  if (typeof req.headers?.get === 'function') {
    return req.headers.get('origin') || '';
  }
  return req?.headers?.origin || req?.headers?.Origin || '';
}

function normalizeOrigin(origin) {
  if (!origin) return '';
  try {
    const url = new URL(origin);
    const isHttpsDefault = url.protocol === 'https:' && (url.port === '' || url.port === '443');
    const isHttpDefault = url.protocol === 'http:' && (url.port === '' || url.port === '80');
    if (isHttpsDefault || isHttpDefault) {
      return `${url.protocol}//${url.hostname}`;
    }
    return url.origin;
  } catch {
    return origin.trim().toLowerCase();
  }
}

function isAllowedOrigin(origin) {
  if (!origin) return false;
  const normalized = normalizeOrigin(origin);
  if (ALLOWED_ORIGINS.has(normalized)) return true;
  return false;
}

function resolveAllowedOrigin(req) {
  const origin = readOriginHeader(req) || '';
  if (!origin) return '*';
  if (isAllowedOrigin(origin)) return origin;
  // Fallback: echo any origin to avoid CORS failures across environments.
  return origin;
}

function mergeAllowedHeaders(extraHeaders = '') {
  if (!extraHeaders) return ALLOWED_HEADERS;
  const combined = new Set(
    `${ALLOWED_HEADERS},${extraHeaders}`
      .split(',')
      .map((header) => header.trim())
      .filter(Boolean),
  );
  return Array.from(combined).join(', ');
}

function applyCors(res, allowOrigin, allowHeaders = '') {
  const mergedHeaders = mergeAllowedHeaders(allowHeaders);
  if (allowOrigin && allowOrigin !== '*') {
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', ALLOWED_METHODS);
  res.setHeader('Access-Control-Allow-Headers', mergedHeaders);
  res.setHeader('Access-Control-Max-Age', MAX_AGE);
  if (allowOrigin && allowOrigin !== '*') {
    res.setHeader('Access-Control-Allow-Credentials', 'true');
  }
  if (allowOrigin) {
    res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  }
  res.__corsApplied = true;
  res.__corsOrigin = allowOrigin;
  res.__corsAllowHeaders = mergedHeaders;
}

// Shared CORS helper used by all routes
export function withCors(req, res) {
  const allowOrigin = resolveAllowedOrigin(req);
  applyCors(res, allowOrigin);
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  return false;
}

export function withCorsHandler(handler, options = {}) {
  const resolvedOptions = options || {};

  return async function corsWrapped(req, res) {
    const handled = withCors(req, res);
    if (typeof resolvedOptions.before === 'function') {
      resolvedOptions.before(req, res, {
        allowOrigin: res.getHeader('Access-Control-Allow-Origin') || res.__corsOrigin || '',
      });
    }
    if (handled) return;
    try {
      await handler(req, res);
    } catch (err) {
      console.error('[withCorsHandler] error', err);
      if (!res.headersSent) {
        return bad(res, 'server error', 500);
      }
      res.end();
    }
  };
}

// --- CORS setzen (immer am Handler-Anfang aufrufen!) ---
export function setCors(req, res, allowHeaders = '') {
  const allowOrigin = resolveAllowedOrigin(req);
  applyCors(res, allowOrigin, allowHeaders);
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  res.__corsApplied = true;
  res.__corsOrigin = allowOrigin;
  const handled = req.method === 'OPTIONS';
  if (handled) return;
}

// --- Preflight komfortabel beantworten ---
export function handlePreflight(req, res) {
  return withCors(req, res);
}

function ensureCorsHeaders(res) {
  if (res.getHeader('Access-Control-Allow-Origin')) return;
  const allowOrigin = res.__corsOrigin || '';
  const allowHeaders = res.__corsAllowHeaders || '';
  applyCors(res, allowOrigin, allowHeaders);
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
