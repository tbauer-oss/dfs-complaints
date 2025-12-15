// /api/gate/index.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, ok, bad, methodNotAllowed, readJson, setCors } from '../_lib/http.js';
import { consumeGateCodeOnce, issueGateToken, GateError } from '../_lib/gate-auth.js';

const isPreview = process.env.VERCEL_ENV !== 'production';

export default async function handler(req, res) {
  // Immer zuerst CORS setzen – auch bei regulären Requests
  // (handlePreflight kümmert sich um OPTIONS)
  setCors(req, res);
  if (handlePreflight(req, res)) return;

  if (req.method === 'GET') {
    return ok(res, { endpoint: 'gate', method: 'GET' });
  }
  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  try {
    const body = readJson(req);
    const emailInput = body.email || body.mail || body.user;
    const codeInput = body.password || body.code || body.pass || body.token;

    const { email } = await consumeGateCodeOnce(emailInput, codeInput);
    const { token, expiresIn } = issueGateToken(email);

    return ok(res, {
      ok: true,
      gate: token,
      token,
      type: 'gate',
      email,
      expiresIn,
    });
  } catch (err) {
    if (err instanceof GateError) {
      return bad(res, err.message, err.statusCode || 400);
    }
    console.error('gate/index fatal:', err);
    const msg = isPreview ? err?.message || String(err) : 'internal error';
    return bad(res, msg, 500);
  }
}
