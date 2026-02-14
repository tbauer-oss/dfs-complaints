export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../_lib/http.js';
import { kvStatus } from '../../_lib/store.js';
import { isAdminUser, portalUserFromRequest } from '../../_lib/portalAuth.js';

function isDevEnvironment() {
  return String(process.env.NODE_ENV || '').trim().toLowerCase() === 'development';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);
  if (!isDevEnvironment()) return bad(res, 'not found', 404);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);
  if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);

  let dbConnected = false;
  try {
    const status = await kvStatus();
    dbConnected = Boolean(status?.ok);
  } catch {
    dbConnected = false;
  }

  return ok(res, {
    dbConnected,
    jwtSecretSet: Boolean(String(process.env.JWT_SECRET || '').trim()),
  });
}
