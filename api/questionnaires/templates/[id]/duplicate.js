// /api/questionnaires/templates/[id]/duplicate – Duplicate template
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { trainingQuestionnaireTemplateDuplicate } from '../../../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    const duplicated = await trainingQuestionnaireTemplateDuplicate(id, {
      createdBy: actor.email,
      updatedBy: actor.email,
    });
    if (!duplicated) return bad(res, 'not found', 404);
    return ok(res, { ok: true, template: duplicated });
  } catch (err) {
    console.error('[questionnaires/templates/duplicate] error', err);
    return bad(res, 'server error', 500);
  }
}
