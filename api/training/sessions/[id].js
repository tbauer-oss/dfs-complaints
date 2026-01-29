// /api/training/sessions/[id].js – Admin delete for Schulungen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingRecordErase, trainingRecordGet, trainingRecordUpdate } from '../../_lib/store.js';

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
      const current = await trainingRecordGet(id);
      if (!current) return bad(res, 'not found', 404);
      if (!canEditAll && current.createdBy !== actor.email) {
        return bad(res, 'forbidden', 403);
      }
      if (body.updatedAt && Number(body.updatedAt) !== Number(current.updatedAt)) {
        return bad(res, 'conflict', 409, { message: 'Datensatz wurde zwischenzeitlich geändert.' });
      }
      const updated = await trainingRecordUpdate(id, { ...body, updatedBy: actor.email });
      return ok(res, { ok: true, record: updated });
    }

    if (req.method === 'DELETE') {
      if (!canEditAll) return bad(res, 'forbidden', 403);
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
