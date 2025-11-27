// api/rep/downloads.js
export const config = { runtime: 'nodejs' };

import { setCors, handlePreflight, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { getRepFromAuthHeader } from '../_lib/repAuth.js';
import { repDownloadsWithBadges } from '../_lib/store.js';
import { loadRepById } from '../_lib/repsStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res, 'Content-Type, Authorization');

  if (req.method !== 'GET') return methodNotAllowed(res);

  try {
    const auth = getRepFromAuthHeader(req);
    if (!auth?.repId) return bad(res, 'unauthorized', 401);
    const rep = await loadRepById(auth.repId);
    if (!rep || rep.active === false) return bad(res, 'unauthorized', 401);

    const items = await repDownloadsWithBadges(rep.id, { includeInactive: false });
    return ok(res, { items });
  } catch (e) {
    console.error('[rep/downloads] failed', e);
    return bad(res, 'internal error', 500);
  }
}
