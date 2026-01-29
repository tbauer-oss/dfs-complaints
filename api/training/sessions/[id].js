// /api/training/sessions/[id].js – Admin delete for Schulungen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingRecordErase } from '../../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;
  if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);

  try {
    if (req.method === 'DELETE') {
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      const deleteInstances = String(req.query?.deleteInstances || readJson(req)?.deleteInstances || '')
        .toLowerCase() === 'true';
      const result = await trainingRecordErase(id, { deleteInstances });
      if (!result.removed) return bad(res, 'not found', 404);
      console.info('[training/sessions] deleted', { id, deleteInstances, by: actor.email, scope: 'single' });
      return ok(res, { ok: true, removed: result.removed });
    }
    return methodNotAllowed(res);
  } catch (err) {
    console.error('[training/sessions] error', err);
    return bad(res, 'server error', 500);
  }
}
