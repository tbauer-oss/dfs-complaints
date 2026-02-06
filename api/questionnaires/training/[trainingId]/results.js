// /api/questionnaires/training/[trainingId]/results – Questionnaire results for training
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import {
  trainingQuestionnairesAll,
  trainingRecordGet,
  trainingQuestionnaireTemplatesAll,
} from '../../../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const trainingId = (req.query?.trainingId || req.query?.id || '').toString();
    if (!trainingId) return bad(res, 'trainingId missing', 400);

    const [assignments, training, templates] = await Promise.all([
      trainingQuestionnairesAll(),
      trainingRecordGet(trainingId),
      trainingQuestionnaireTemplatesAll(),
    ]);

    if (!training) return bad(res, 'not found', 404);

    const templateMap = new Map(templates.map((t) => [t.id, t]));
    const list = assignments.filter((entry) => entry.trainingId === trainingId && entry.purpose === 'wk');

    const totals = list.reduce(
      (acc, entry) => {
        const status = (entry.status || '').toString();
        if (status === 'passed') acc.passed += 1;
        if (status === 'failed') acc.failed += 1;
        if (status === 'open' || status === 'in_progress') acc.open += 1;
        if (status === 'submitted' || status === 'evaluated') acc.submitted += 1;
        if (entry.scorePercent) {
          acc.scoreSum += Number(entry.scorePercent || 0);
          acc.scoreCount += 1;
        }
        return acc;
      },
      { open: 0, submitted: 0, passed: 0, failed: 0, scoreSum: 0, scoreCount: 0 },
    );

    const averageScore = totals.scoreCount ? Math.round(totals.scoreSum / totals.scoreCount) : 0;

    const detailed = list.map((entry) => {
      const template = templateMap.get(entry.templateId) || null;
      return {
        ...entry,
        templateTitle: template?.title || '',
      };
    });

    return ok(res, {
      ok: true,
      training,
      summary: {
        total: list.length,
        open: totals.open,
        submitted: totals.submitted,
        passed: totals.passed,
        failed: totals.failed,
        averageScore,
      },
      list: detailed,
    });
  } catch (err) {
    console.error('[questionnaires/training/results] error', err);
    return bad(res, 'server error', 500);
  }
}
