// /api/training/templates/[id].js – Admin delete for Fragebogen-Templates
export const config = { runtime: 'nodejs' };

import { withCorsHandler, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requireTrainingScopeAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import {
  trainingQuestionnaireTemplateDelete,
  trainingQuestionnaireTemplateUpdate,
  trainingTemplateGet,
} from '../../_lib/store.js';

const TRAINING_TILE = 'trainingEffectiveness';

async function handler(req, res) {
  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;
  const canEditAll = isAdminUser(actor);

  try {
    if (req.method === 'PATCH') {
      const body = readJson(req) || {};
      const id = req.query?.id || body.id;
      if (!id) return bad(res, 'id missing', 400);
      const current = await trainingTemplateGet(id);
      if (!current) return bad(res, 'not found', 404);
      if (!canEditAll && current.createdBy !== actor.email) {
        return bad(res, 'forbidden', 403);
      }
      if (body.updatedAt && Number(body.updatedAt) !== Number(current.updatedAt)) {
        return bad(res, 'conflict', 409, { message: 'Datensatz wurde zwischenzeitlich geändert.' });
      }
      const updated = await trainingQuestionnaireTemplateUpdate(id, { ...body, updatedBy: actor.email });
      return ok(res, { ok: true, template: updated });
    }

    if (req.method === 'DELETE') {
      if (!canEditAll) return bad(res, 'forbidden', 403);
      const id = req.query?.id || readJson(req)?.id;
      if (!id) return bad(res, 'id missing', 400);
      await trainingQuestionnaireTemplateDelete(id);
      console.info('[training/templates] deleted', { id, by: actor.email, scope: 'single' });
      return ok(res, { ok: true });
    }
    return methodNotAllowed(res);
  } catch (err) {
    console.error('[training/templates] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler);
