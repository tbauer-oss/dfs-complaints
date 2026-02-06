// /api/questionnaires/templates – Public template access
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  trainingQuestionnaireTemplatesAll,
  trainingQuestionnaireTemplateSave,
} from '../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['POST'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET') {
      const list = await trainingQuestionnaireTemplatesAll();
      return ok(res, { ok: true, list });
    }

    if (req.method === 'POST') {
      const body = readJson(req) || {};
      const saved = await trainingQuestionnaireTemplateSave({
        ...body,
        createdBy: actor.email,
        updatedBy: actor.email,
      });
      return ok(res, { ok: true, template: saved });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[questionnaires/templates] error', err);
    return bad(res, 'server error', 500);
  }
}
