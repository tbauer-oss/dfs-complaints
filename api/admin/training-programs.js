// /api/admin/training-programs.js – Jahres-Schulungsprogramme
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requireTrainingScopeAccess } from './_guard.js';
import { isAdminUser } from '../_lib/portalAuth.js';
import {
  trainingProgramsAll,
  trainingProgramGet,
  trainingProgramSave,
  trainingProgramUpdate,
  trainingProgramDelete,
  trainingProgramNeedLinksAll,
} from '../_lib/store.js';
import { validateTrainingProgram } from '../_lib/trainingValidation.js';

const TRAINING_TILE = 'trainingProgram';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await trainingProgramsAll();
      const links = await trainingProgramNeedLinksAll();
      const year = Number(req.query?.year || 0);
      const filtered = year ? list.filter((entry) => entry.year === year) : list;
      const enriched = filtered.map((entry) => ({
        ...entry,
        needLinks: links.filter((link) => link.programEntryId === entry.id),
      }));
      return ok(res, { ok: true, list: enriched });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const { errors, normalizedPeriod } = validateTrainingProgram(body);
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      const saved = await trainingProgramSave({
        ...body,
        plannedPeriodValue: normalizedPeriod || body.plannedPeriodValue,
        createdBy: actor.email,
        updatedBy: actor.email,
      });
      return ok(res, { ok: true, program: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const { errors, normalizedPeriod } = validateTrainingProgram({ ...body, year: body.year || body.programYear });
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      const current = await trainingProgramGet(id);
      if (!current) return bad(res, 'not found', 404);
      if (body.updatedAt && Number(body.updatedAt) !== Number(current.updatedAt)) {
        return bad(res, 'conflict', 409, { message: 'Datensatz wurde zwischenzeitlich geändert.' });
      }
      const updated = await trainingProgramUpdate(id, {
        ...body,
        plannedPeriodValue: normalizedPeriod || body.plannedPeriodValue,
        updatedBy: actor.email,
      });
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
