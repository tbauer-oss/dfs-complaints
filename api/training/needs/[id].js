// /api/training/needs/[id].js – Admin delete for Schulungsbedarfe
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingNeedDelete, trainingNeedGet, trainingNeedUpdate } from '../../_lib/store.js';
import { validateTrainingNeed } from '../../_lib/trainingValidation.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;
  const canEditAll = isAdminUser(actor);

  try {
    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = req.query?.id || body.id;
      if (!id) return bad(res, 'id missing', 400);
      const current = await trainingNeedGet(id);
      if (!current) return bad(res, 'not found', 404);
      if (!canEditAll && current.createdBy !== actor.email) {
        return bad(res, 'forbidden', 403);
      }
      if (body.updatedAt && Number(body.updatedAt) !== Number(current.updatedAt)) {
        return bad(res, 'conflict', 409, { message: 'Datensatz wurde zwischenzeitlich geändert.' });
      }
      const { errors, normalizedPeriod } = validateTrainingNeed(body);
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      const updated = await trainingNeedUpdate(id, {
        ...body,
        plannedPeriodValue: normalizedPeriod || body.plannedPeriodValue,
        updatedBy: actor.email,
      });
      return ok(res, { ok: true, need: updated });
    }

    if (req.method === 'DELETE') {
      if (!canEditAll) return bad(res, 'forbidden', 403);
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
