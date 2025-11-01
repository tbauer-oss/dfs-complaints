// api/_lib/http.js  (ESM, Vercel)

// --- Freigegebene Frontend-Origins ---
const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const LOCAL_FE = 'http://localhost:8080';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

// Für Vercel Node.js Runtime (optional pro-File, hier zentral okay)
export const config = { runtime: 'nodejs' };

// Prüft, ob Origin erlaubt ist
function isAllowedOrigin(origin = '') {
  if (!origin) return false;
  if (origin === PROD_FE || origin === LOCAL_FE) return true;
  return PREVIEW.test(origin);
}

// Setzt CORS-Header (immer am Handler-Anfang aufrufen!)
export function setCors(req, res) {
  const origin = req.headers?.origin || '';
  const allow = isAllowedOrigin(origin) ? origin : PROD_FE;

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  // Wichtig: Authorization/X-Admin-Secret/X-Gate zulassen
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret, X-Gate');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
}

// 204 für Preflight
export function noContent(res) {
  res.statusCode = 204;
  res.end();
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

// JSON-Body robust lesen (Vercel liefert bei kleinen Bodies oft schon geparst)
export function readJson(req) {
  if (req?.body && typeof req.body === 'object') return req.body;
  try {
    return JSON.parse(req?.body ?? '{}');
  } catch {
    return {};
  }
}
