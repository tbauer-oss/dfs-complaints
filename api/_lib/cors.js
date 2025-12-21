// api/_lib/cors.js
// Centralized CORS helper for consistent admin/portal endpoints.

const ALLOWED_ORIGINS = new Set(['https://dfs-complaints-web.vercel.app']);
const LOCAL_PATTERN = /^https?:\/\/localhost(?::\d+)?$/i;
const BASE_HEADERS = ['Content-Type', 'Authorization', 'X-Requested-With'];

function resolveAllowedOrigin(origin = '') {
  if (!origin) return '';
  if (ALLOWED_ORIGINS.has(origin) || LOCAL_PATTERN.test(origin)) return origin;
  return '';
}

function mergedAllowedHeaders(custom = '') {
  const extras = String(custom || '')
    .split(',')
    .map((h) => h.trim())
    .filter(Boolean);
  return [...BASE_HEADERS, ...extras]
    .map((h) => h.toLowerCase())
    .filter((h, idx, arr) => arr.indexOf(h) === idx)
    .map((h) =>
      h
        .split('-')
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join('-')
    )
    .join(', ');
}

export function applyCors(req, res, { allowHeaders = '', allowCredentials = false } = {}) {
  const origin = resolveAllowedOrigin(req?.headers?.origin || '');
  if (origin) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    if (allowCredentials) {
      res.setHeader('Access-Control-Allow-Credentials', 'true');
    }
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', mergedAllowedHeaders(allowHeaders));
  res.setHeader('Access-Control-Max-Age', '86400');
  res.__corsApplied = true;
  res.__corsOrigin = origin;

  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  return false;
}
