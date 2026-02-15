export const config = { runtime: 'nodejs' };

import { bad, handlePreflight, methodNotAllowed, ok, readJson, setCors } from '../../_lib/http.js';
import { portalUserFromRequest } from '../../_lib/portalAuth.js';
import { markPortalTourSeen } from '../../_lib/store.js';

function isStoreUnavailable(error) {
  const code = String(error?.code || '').toUpperCase();
  return code === 'STORE_UNAVAILABLE' || code === 'DB_UNAVAILABLE';
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await portalUserFromRequest(req);
  if (!actor?.email) {
    return bad(res, 'unauthorized', 401, { code: 'UNAUTHORIZED' });
  }

  const body = await readJson(req);
  const seen = body?.seen !== false;

  try {
    const updated = await markPortalTourSeen(actor.email, { seen });
    if (!updated) {
      return bad(res, 'unauthorized', 401, { code: 'UNAUTHORIZED' });
    }
    return ok(res, { ok: true, tourSeen: updated.tourSeen === true });
  } catch (error) {
    if (isStoreUnavailable(error)) {
      return bad(res, 'Service temporär nicht verfügbar. Bitte später erneut versuchen.', 503, {
        code: 'STORE_UNAVAILABLE',
      });
    }
    console.error('portal/tour/seen failed', error);
    return bad(res, 'internal error', 500, { code: 'INTERNAL_ERROR' });
  }
}
