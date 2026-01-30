// /api/ui-config/me/reset.js – User-Layout zurücksetzen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../_lib/http.js';
import { loadPortalUserUiConfig, resetPortalUserUiConfig } from '../../_lib/store.js';
import { portalUserFromRequest } from '../../_lib/portalAuth.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await portalUserFromRequest(req);
  if (!actor) return bad(res, 'unauthorized', 401);

  await resetPortalUserUiConfig(actor.email);
  const config = await loadPortalUserUiConfig(actor.email);
  return ok(res, { ok: true, config });
}
