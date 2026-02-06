// /api/account_export.js – DSGVO Self-Service Datenexport (Art. 15/20)
export const config = { runtime: 'nodejs' };

import {
  handlePreflight,
  setCors,
  ok,
  bad,
  methodNotAllowed,
} from './_lib/http.js';
import { getAuthUser } from './_lib/auth.js';
import { userByEmail, complaintsByEmail } from './_lib/store.js';

function sanitizeAccount(u) {
  if (!u || typeof u !== 'object') return {};
  const { passhash, password, resetToken, reset_token, ...rest } = u;
  return rest;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const auth = getAuthUser(req);
  if (!auth) return bad(res, 'unauthorized', 401);

  try {
    const user = await userByEmail(auth.email);
    if (!user) return bad(res, 'not found', 404);

    const complaints = await complaintsByEmail(auth.email);
    const payload = {
      account: sanitizeAccount(user),
      complaints: Array.isArray(complaints) ? complaints : [],
    };

    return ok(res, payload);
  } catch (e) {
    console.error('[account_export] error:', e);
    return bad(res, 'server error', 500);
  }
}
