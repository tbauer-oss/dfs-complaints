// /api/admin/training-questionnaire-templates.js – Fragebogen-Templates
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requireTrainingScopeAccess } from './_guard.js';
import { isAdminUser } from '../_lib/portalAuth.js';
import {
  trainingQuestionnaireTemplatesAll,
  trainingQuestionnaireTemplateSave,
  trainingQuestionnaireTemplateUpdate,
  trainingQuestionnaireTemplateDelete,
} from '../_lib/store.js';

const TRAINING_TILE = 'trainingEffectiveness';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST', 'PATCH', 'DELETE'].includes(req.method);
  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await trainingQuestionnaireTemplatesAll();
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const saved = await trainingQuestionnaireTemplateSave({ ...body, createdBy: actor.email, updatedBy: actor.email });
      return ok(res, { ok: true, template: saved });
    }

    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = body.id || req.query?.id;
      if (!id) return bad(res, 'id missing', 400);
      const updated = await trainingQuestionnaireTemplateUpdate(id, { ...body, updatedBy: actor.email });
      if (!updated) return bad(res, 'not found', 404);
      return ok(res, { ok: true, template: updated });
    }

    if (req.method === 'DELETE') {
      if (!isAdminUser(actor)) {
        return bad(res, 'forbidden', 403);
      }
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      await trainingQuestionnaireTemplateDelete(id);
      console.info('[training-questionnaire-templates] deleted', { id, by: actor.email, scope: 'single' });
      return ok(res, { ok: true });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[admin/training-questionnaire-templates] error', err);
    return bad(res, 'server error', 500);
  }
}
