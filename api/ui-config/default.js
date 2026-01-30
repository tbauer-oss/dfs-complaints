// /api/ui-config/default.js – Öffentliche Default-UI-Konfiguration (Portal)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { loadPortalAdminUi } from '../_lib/store.js';
import { portalUserFromRequest } from '../_lib/portalAuth.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  const config = await loadPortalAdminUi().catch(() => ({}));
  return ok(res, { ok: true, config });
}
