// /api/auth/register.js
export const config = { runtime: 'nodejs' };

const PROD_FE  = 'https://dfs-complaints-web.vercel.app';
const PREVIEW  = /^https:\/\/dfs-complaints-web-[a-z0-9-]+(?:-[a-z0-9-]+)?\.vercel\.app$/i;

function setTestCors(req, res) {
  const origin = req.headers?.origin || '';
  const allow = origin && (origin === PROD_FE || PREVIEW.test(origin)) ? origin : PROD_FE;

  res.setHeader('Access-Control-Allow-Origin', allow);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Admin-Secret');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('X-Debug-CORS', 'register:hit');   // <-- Sichtbarer Marker
}

export default async function handler(req, res) {
  setTestCors(req, res);

  // Preflight knallhart beenden
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    return res.end();
  }

  if (req.method !== 'POST') {
    res.statusCode = 405;
    return res.end(JSON.stringify({ error: 'method not allowed' }));
  }

  // NICHTS weiter machen – nur beweisen, dass CORS/Route funktionieren
  res.statusCode = 200;
  return res.end(JSON.stringify({ ok: true, echo: 'register-test' }));
}
