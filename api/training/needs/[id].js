// /api/training/needs/[id].js – Admin delete for Schulungsbedarfe
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingNeedDelete } from '../../_lib/store.js';

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
      const result = await trainingNeedDelete(id, { deleteInstances });
      console.info('[training/needs] deleted', { id, deleteInstances, by: actor.email, scope: 'single' });
      return ok(res, { ok: true, removed: result.removed });
    }
    return methodNotAllowed(res);
  } catch (err) {
    console.error('[training/needs] error', err);
    return bad(res, 'server error', 500);
  }
}
