// /api/questionnaires/templates/[id] – Template detail
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import {
  trainingQuestionnaireTemplatesAll,
  trainingQuestionnaireTemplateUpdate,
  trainingQuestionnaireTemplateDelete,
} from '../../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['PUT', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    if (req.method === 'GET') {
      const list = await trainingQuestionnaireTemplatesAll();
      const template = list.find((entry) => entry.id === id);
      if (!template) return bad(res, 'not found', 404);
      return ok(res, { ok: true, template });
    }

    if (req.method === 'PUT' || req.method === 'PATCH') {
      const body = readJson(req) || {};
      const updated = await trainingQuestionnaireTemplateUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, template: updated });
    }

    if (req.method === 'DELETE') {
      if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);
      await trainingQuestionnaireTemplateDelete(id);
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[questionnaires/templates/id] error', err);
    return bad(res, 'server error', 500);
  }
}
