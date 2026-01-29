// /api/admin/training-programs.js – Jahres-Schulungsprogramme
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { isAdminUser } from '../_lib/portalAuth.js';
import {
  trainingProgramsAll,
  trainingProgramSave,
  trainingProgramUpdate,
  trainingProgramDelete,
} from '../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await trainingProgramsAll();
      const year = Number(req.query?.year || 0);
      const filtered = year ? list.filter((entry) => entry.year === year) : list;
      return ok(res, { ok: true, list: filtered });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const saved = await trainingProgramSave({ ...body, createdBy: actor.email, updatedBy: actor.email });
      return ok(res, { ok: true, program: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const updated = await trainingProgramUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, program: updated });
    }

    if (req.method === 'DELETE') {
      if (!isAdminUser(actor)) {
        return bad(res, 'forbidden', 403);
      }
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      await trainingProgramDelete(id);
      console.info('[training-programs] deleted', { id, by: actor.email, scope: 'single' });
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/training-programs] error', err);
    return bad(res, 'server error', 500);
  }
}
