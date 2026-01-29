// /api/questionnaires/assignments/[id] – Questionnaire runner data
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingQuestionnaireGet, trainingTemplateGet, trainingRecordGet } from '../../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    const assignment = await trainingQuestionnaireGet(id);
    if (!assignment) return bad(res, 'not found', 404);

    const isAdmin = isAdminUser(actor);
    const actorId = (actor.email || '').toString().toLowerCase();
    if (!isAdmin) {
      const assignedId = (assignment.assignedToUserId || assignment.participantId || '').toLowerCase();
      if (!assignedId || assignedId !== actorId) return bad(res, 'forbidden', 403);
    }

    const template = await trainingTemplateGet(assignment.templateId);
    const training = assignment.trainingId ? await trainingRecordGet(assignment.trainingId) : null;

    return ok(res, { ok: true, assignment, template, training });
  } catch (err) {
    console.error('[questionnaires/assignments/id] error', err);
    return bad(res, 'server error', 500);
  }
}
