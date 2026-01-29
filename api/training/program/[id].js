// /api/training/program/[id].js – Admin delete for Schulungsprogramme
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingProgramDelete } from '../../_lib/store.js';

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
      await trainingProgramDelete(id);
      console.info('[training/program] deleted', { id, by: actor.email, scope: 'single' });
      return ok(res, { ok: true });
    }
    return methodNotAllowed(res);
  } catch (err) {
    console.error('[training/program] error', err);
    return bad(res, 'server error', 500);
  }
}
