// /api/questionnaires/assign – Create questionnaire assignments
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  trainingQuestionnairesAll,
  trainingQuestionnaireSave,
  trainingTemplateGet,
} from '../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;

  try {
    const body = readJson(req) || {};
    const trainingSessionId = (body.trainingSessionId || body.trainingId || '').toString();
    const templateId = (body.templateId || body.questionnaireTemplateId || '').toString();
    const participantIds = Array.isArray(body.participantIds)
      ? body.participantIds.map((entry) => entry.toString())
      : [];
    if (!templateId || !participantIds.length) return bad(res, 'templateId and participantIds required', 400);

    const template = await trainingTemplateGet(templateId);
    const defaultThreshold = Number(template?.defaultThresholdPercent ?? 70);
    const thresholdPercent = Number(body.thresholdPercent ?? defaultThreshold);
    if (!Number.isFinite(thresholdPercent) || thresholdPercent < 0 || thresholdPercent > 100) {
      return bad(res, 'thresholdPercent invalid', 400);
    }

    const dueAt = body.dueAt == null ? null : Number(body.dueAt);
    const existing = await trainingQuestionnairesAll();
    const existingKeys = new Set(existing.map((q) => `${q.trainingId}:${q.assignedToUserId}:${q.purpose || 'wk'}`));

    const created = [];
    for (const participantId of participantIds) {
      const key = `${trainingSessionId}:${participantId}:${body.purpose || 'wk'}`;
      if (existingKeys.has(key)) continue;
      const saved = await trainingQuestionnaireSave({
        trainingId: trainingSessionId,
        participantId,
        assignedToUserId: participantId,
        assignedByUserId: actor.email,
        templateId,
        purpose: body.purpose || 'wk',
        status: 'open',
        thresholdPercent,
        dueAt,
        createdBy: actor.email,
        updatedBy: actor.email,
      });
      created.push(saved);
    }

    return ok(res, { ok: true, assignments: created });
  } catch (err) {
    console.error('[questionnaires/assign] error', err);
    return bad(res, 'server error', 500);
  }
}
