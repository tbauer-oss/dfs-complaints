// /api/admin/training/purge.js – Bulk delete for training module data
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import {
  trainingNeedsPurge,
  trainingProgramsPurge,
  trainingRecordsPurge,
  trainingTemplatesPurge,
  trainingQuestionnairesPurge,
} from '../../_lib/store.js';

const TRAINING_TILE = 'trainings';
const SCOPES = new Set(['all', 'needs', 'sessions', 'program', 'templates']);

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;
  if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);

  try {
    if (req.method !== 'POST') return methodNotAllowed(res);
    const body = readJson(req) || {};
    const scope = String(body.scope || '').trim();
    const confirm = String(body.confirm || '').trim().toUpperCase();
    if (!SCOPES.has(scope)) return bad(res, 'scope invalid', 400);
    if (confirm !== 'LOESCHEN') return bad(res, 'confirmation required', 400);

    const results = {};
    if (scope === 'all' || scope === 'needs') {
      results.needs = await trainingNeedsPurge();
    }
    if (scope === 'all' || scope === 'program') {
      results.program = await trainingProgramsPurge();
    }
    if (scope === 'all' || scope === 'sessions') {
      results.sessions = await trainingRecordsPurge();
      results.questionnaires = await trainingQuestionnairesPurge();
    }
    if (scope === 'all' || scope === 'templates') {
      results.templates = await trainingTemplatesPurge();
    }

    console.info('[training/purge] deleted', { scope, by: actor.email, results });
    return ok(res, { ok: true, results });
  } catch (err) {
    console.error('[training/purge] error', err);
    return bad(res, 'server error', 500);
  }
}
