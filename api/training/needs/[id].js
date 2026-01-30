// /api/training/needs/[id].js – Admin delete for Schulungsbedarfe
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { withCors } from '../../_lib/withCors.ts';
import { requireTrainingNeedAccess } from '../../admin/_guard.js';
import { PORTAL_ROLES, normalizeRole } from '../../_lib/portalAuth.js';
import { trainingNeedDelete, trainingNeedGet, trainingNeedUpdate } from '../../_lib/store.js';
import { validateTrainingNeed } from '../../_lib/trainingValidation.js';

async function handler(req, res) {
  const actor = await requireTrainingNeedAccess(req, res, { write: true });
  if (!actor) return;
  const role = normalizeRole(actor.role);
  const canEditAll = role === PORTAL_ROLES.superuser || role === PORTAL_ROLES.admin;

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
      console.info('[training/needs] updated', { id, by: actor.email });
      return ok(res, { ok: true, need: updated });
    }

    if (req.method === 'DELETE') {
      if (role !== PORTAL_ROLES.superuser) {
        console.warn('[training/needs] delete denied', { id: req.query?.id, by: actor.email });
        return bad(res, 'forbidden', 403);
      }
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

export default withCors(handler);
