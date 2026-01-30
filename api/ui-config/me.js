// /api/ui-config/me.js – User-spezifische UI-Konfiguration (Portal)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { loadPortalUserUiConfig, savePortalUserUiConfig } from '../_lib/store.js';
import { portalUserFromRequest } from '../_lib/portalAuth.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  if (req.method === 'GET') {
    const config = await loadPortalUserUiConfig(actor.email);
    return ok(res, { ok: true, config });
  }

  if (req.method === 'PUT') {
    const body = readJson(req) || {};
    const config = await savePortalUserUiConfig(actor.email, body);
    return ok(res, { ok: true, config });
  }

  return methodNotAllowed(res);
}
