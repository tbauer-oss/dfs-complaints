// /api/questionnaires/my – List assignments for current user
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { trainingQuestionnairesAll, trainingRecordsAll, trainingQuestionnaireTemplatesAll } from '../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const userId = (actor.email || '').toString().toLowerCase();
    const [assignments, trainings, templates] = await Promise.all([
      trainingQuestionnairesAll(),
      trainingRecordsAll(),
      trainingQuestionnaireTemplatesAll(),
    ]);

    const trainingMap = new Map(trainings.map((t) => [t.id, t]));
    const templateMap = new Map(templates.map((t) => [t.id, t]));

    const list = assignments
      .filter((entry) => (entry.assignedToUserId || entry.participantId || '').toLowerCase() === userId)
      .map((entry) => ({
        ...entry,
        training: trainingMap.get(entry.trainingId) || null,
        template: templateMap.get(entry.templateId) || null,
      }));

    return ok(res, { ok: true, list });
  } catch (err) {
    console.error('[questionnaires/my] error', err);
    return bad(res, 'server error', 500);
  }
}
