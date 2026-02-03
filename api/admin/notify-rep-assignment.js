// api/admin/notify-rep-assignment.js
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') {
    return methodNotAllowed(res);
  }

  const actor = await requirePortalAccess(req, res, { write: true, tile: 'reps' });
  if (!actor) return;

  return ok(res, { ok: true });
}
