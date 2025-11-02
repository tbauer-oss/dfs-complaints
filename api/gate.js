// /api/gate.js
export const config = { runtime: 'nodejs' };

import {
  handlePreflight, ok, bad, methodNotAllowed, readJson
} from './_lib/http.js';

export default async function handler(req, res) {
  // CORS-Header setzen + OPTIONS sofort beantworten
  if (handlePreflight(req, res)) return;

  if (req.method === 'GET') {
    return ok(res, { endpoint: 'gate', method: 'GET' });
  }
  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  const PASS = process.env.AUTH_PASSWORD || '';
  if (!PASS) return bad(res, 'AUTH_PASSWORD missing', 500);

  try {
    const body = readJson(req);
    const pwd  = String(body?.password || '').trim();

    if (!pwd)         return bad(res, 'password required', 400);
    if (pwd !== PASS) return bad(res, 'invalid', 401);

    // Antwort kompatibel zu deinem Client (ok ODER gate-String)
    return ok(res, { ok: true, gate: 'open' });
  } catch {
    return bad(res, 'bad request', 400);
  }
}
