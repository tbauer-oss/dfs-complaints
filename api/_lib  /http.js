// api/_lib/http.js  (ESM)

const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const LOCAL_FE = 'http://localhost:8080';

function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (origin === PROD_FE || origin === LOCAL_FE) return true;
  // Preview-URLs deines FE-Projekts erlauben
  const re = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;
  return re.test(origin);
}

export function setCors(req, res) {
  const origin = req.headers?.origin || '';
  const ok = isAllowedOrigin(origin);
  res.setHeader('Access-Control-Allow-Origin', ok ? origin : PROD_FE);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate');
}

export const noContent = (res) => { res.statusCode = 204; res.end(); };

export const ok = (res, data) => {
  res.setHeader('Content-Type', 'application/json');
  res.statusCode = 200;
  res.end(JSON.stringify(data));
};

export const bad = (res, msg = 'bad request', code = 400) => {
  res.setHeader('Content-Type', 'application/json');
  res.statusCode = code;
  res.end(JSON.stringify({ error: msg }));
};

export const methodNotAllowed = (res) => bad(res, 'method not allowed', 405);

export function readJson(req) {
  if (req?.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req?.body ?? '{}'); } catch { return {}; }
}
