// /api/admin/trainings.js – Einzelmaßnahmen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from './_guard.js';
import { isAdminUser } from '../_lib/portalAuth.js';
import { validateTrainingSession } from '../_lib/trainingValidation.js';
import {
  trainingRecordsAll,
  trainingRecordGet,
  trainingRecordSave,
  trainingRecordUpdate,
  trainingRecordDelete,
} from '../_lib/store.js';

const TRAINING_TILE = 'trainings';

function summarize(list) {
  const total = list.length;
  const completed = list.filter((entry) => entry.status === 'completed').length;
  const planned = list.filter((entry) => ['draft', 'planned', 'scheduled', 'inProgress'].includes(entry.status)).length;
  const participants = list.flatMap((entry) => entry.participants || []);
  const attended = participants.filter((p) => p.status === 'attended').length;
  const invited = participants.length;
  return {
    total,
    completed,
    planned,
    participationRate: invited ? Math.round((attended / invited) * 100) : 0,
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const id = (req.query?.id || req.query?.number || '').toString().trim();
      if (id) {
        const record = await trainingRecordGet(id);
        if (!record) return bad(res, 'not found', 404);
        return ok(res, { ok: true, record });
      }
      const list = await trainingRecordsAll();
      const year = Number(req.query?.year || 0);
      const includeDeleted = String(req.query?.includeDeleted || '').toLowerCase() === 'true';
      const filtered = list.filter((entry) => (includeDeleted ? true : !entry.deletedAt));
      const byYear = year ? filtered.filter((entry) => entry.year === year) : filtered;
      if (req.query?.summary) {
        return ok(res, { ok: true, summary: summarize(byYear) });
      }
      return ok(res, { ok: true, list: byYear });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const { errors } = validateTrainingSession(body);
      if (Object.keys(errors).length) {
        const first = Object.values(errors)[0];
        return bad(res, first, 400, { errors });
      }
      const saved = await trainingRecordSave({ ...body, createdBy: actor.email, updatedBy: actor.email });
      return ok(res, { ok: true, record: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const { errors } = validateTrainingSession(body);
      if (Object.keys(errors).length) {
        const first = Object.values(errors)[0];
        return bad(res, first, 400, { errors });
      }
      const id = body.id || body.trainingNumber || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const updated = await trainingRecordUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, record: updated });
    }

    if (req.method === 'DELETE') {
      if (!isAdminUser(actor)) {
        return bad(res, 'forbidden', 403);
      }
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      const deleted = await trainingRecordDelete(id, { deletedBy: actor.email });
      if (!deleted) return bad(res, 'not found', 404);
      console.info('[trainings] deleted', { id, by: actor.email, scope: 'single' });
      return ok(res, { ok: true, record: deleted });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/trainings] error', err);
    return bad(res, 'server error', 500);
  }
}
