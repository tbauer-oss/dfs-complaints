// /api/admin/training-needs.js – Schulungsbedarfe (FB620)
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import {
  trainingNeedsAll,
  trainingNeedSave,
  trainingNeedUpdate,
  trainingNeedDelete,
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
      const list = await trainingNeedsAll();
      const year = Number(req.query?.year || 0);
      const filtered = year ? list.filter((entry) => entry.year === year) : list;
      return ok(res, { ok: true, list: filtered });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const saved = await trainingNeedSave({ ...body, createdBy: actor.email, updatedBy: actor.email });
      return ok(res, { ok: true, need: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const updated = await trainingNeedUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, need: updated });
    }

    if (req.method === 'DELETE') {
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      await trainingNeedDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/training-needs] error', err);
    return bad(res, 'server error', 500);
  }
}
