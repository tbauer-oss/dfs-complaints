// api/_lib/cors.js
// Centralized CORS helper for all API routes

export const ALLOWED_ORIGIN = 'https://dfs-complaints-web.vercel.app';
const ALLOWED_METHODS = 'GET,POST,PUT,PATCH,DELETE,OPTIONS';
const ALLOWED_HEADERS = 'Content-Type, Authorization';
const MAX_AGE = '86400';

function applyCorsHeaders(res, { allowCredentials = true } = {}) {
  res.setHeader('Access-Control-Allow-Origin', ALLOWED_ORIGIN);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', ALLOWED_METHODS);
  res.setHeader('Access-Control-Allow-Headers', ALLOWED_HEADERS);
  res.setHeader('Access-Control-Max-Age', MAX_AGE);
  if (allowCredentials) {
    res.setHeader('Access-Control-Allow-Credentials', 'true');
  }
  res.__corsApplied = true;
}

export function setCors(req, res) {
  applyCorsHeaders(res);
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

export function handlePreflight(req, res) {
  return setCors(req, res);
}

export function ensureCorsHeaders(res) {
  if (res.getHeader('Access-Control-Allow-Origin')) return;
  applyCorsHeaders(res);
  if (!res.getHeader('Content-Type')) {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
}
