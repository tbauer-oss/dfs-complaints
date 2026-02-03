// api/_lib/http.js  (ESM, shared HTTP helpers)

function ensureJsonContentType(res) {
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
}

// Preflight helper (CORS policy is defined in vercel.json)
export function withCors(req, res) {
  ensureJsonContentType(res);
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
    if (handled) return;
    if (typeof resolvedOptions.before === 'function') {
      resolvedOptions.before(req, res, { allowOrigin: res.getHeader('Access-Control-Allow-Origin') || '' });
    }
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

// --- Preflight helper (CORS policy is defined in vercel.json) ---
export function setCors(req, res, allowHeaders = '') {
  void allowHeaders;
  return withCors(req, res);
}

// --- Preflight komfortabel beantworten ---
export function handlePreflight(req, res) {
  return withCors(req, res);
}

function ensureCorsHeaders(res) {
  ensureJsonContentType(res);
}

// --- 200 OK (JSON) ---
export function ok(res, data) {
  // Content-Type zur Sicherheit
  ensureCorsHeaders(res);
  res.statusCode = 200;
  res.end(JSON.stringify(data ?? {}));
}

// --- Fehlerantwort ---
export function bad(res, msg = 'bad request', code = 400, extra = undefined) {
  ensureCorsHeaders(res);
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
