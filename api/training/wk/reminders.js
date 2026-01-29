// /api/training/wk/reminders – Due/overdue Wirksamkeitskontrollen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingRecordsAll, trainingQuestionnairesAll } from '../../_lib/store.js';

const TRAINING_TILE = 'trainings';

function summarizeTraining(training) {
  return {
    id: training.id,
    trainingNumber: training.trainingNumber,
    title: training.title,
    status: training.status,
    wkMethod: training.wkMethod,
    wkStatus: training.wkStatus,
    wkDueAt: training.wkDueAt,
    wkResponsibleId: training.wkResponsibleId,
    completedAt: training.completedAt,
  };
}

function summarizeAssignment(assignment, training) {
  return {
    id: assignment.id,
    trainingId: assignment.trainingId,
    participantId: assignment.participantId,
    assignedToUserId: assignment.assignedToUserId,
    templateId: assignment.templateId,
    status: assignment.status,
    scorePercent: assignment.scorePercent,
    thresholdPercent: assignment.thresholdPercent,
    dueAt: assignment.dueAt,
    needsRetraining: assignment.needsRetraining,
    trainingNumber: training?.trainingNumber,
    trainingTitle: training?.title,
  };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const now = Date.now();
    const [list, assignments] = await Promise.all([trainingRecordsAll(), trainingQuestionnairesAll()]);
    const isAdmin = isAdminUser(actor);
    const actorMail = (actor.email || '').toString().toLowerCase();
    const filtered = list.filter((training) => {
      if (!training.wkMethod || !training.wkDueAt || training.wkStatus === 'done') return false;
      if (isAdmin) return true;
      const responsible = (training.wkResponsibleId || '').toString().toLowerCase();
      return responsible && responsible === actorMail;
    });

    const dueSoon = filtered.filter((training) => training.wkDueAt >= now && training.wkDueAt <= now + 14 * 24 * 60 * 60 * 1000);
    const overdue = filtered.filter((training) => training.wkDueAt < now);

    const trainingMap = new Map(list.map((training) => [training.id, training]));
    const assignmentFiltered = assignments.filter((entry) => {
      if (entry.purpose !== 'wk') return false;
      if (isAdmin) return true;
      const assignedTo = (entry.assignedToUserId || entry.participantId || '').toString().toLowerCase();
      const training = trainingMap.get(entry.trainingId || '');
      const responsible = (training?.wkResponsibleId || '').toString().toLowerCase();
      return assignedTo === actorMail || (responsible && responsible === actorMail);
    });
    const assignmentDueSoon = assignmentFiltered.filter(
      (entry) =>
        entry.dueAt &&
        ['open', 'in_progress'].includes(entry.status) &&
        entry.dueAt >= now &&
        entry.dueAt <= now + 14 * 24 * 60 * 60 * 1000,
    );
    const assignmentOverdue = assignmentFiltered.filter(
      (entry) => entry.dueAt && ['open', 'in_progress'].includes(entry.status) && entry.dueAt < now,
    );
    const retraining = assignmentFiltered.filter((entry) => entry.needsRetraining);

    return ok(res, {
      ok: true,
      dueSoon: dueSoon.map(summarizeTraining),
      overdue: overdue.map(summarizeTraining),
      questionnaireDueSoon: assignmentDueSoon.map((entry) => summarizeAssignment(entry, trainingMap.get(entry.trainingId))),
      questionnaireOverdue: assignmentOverdue.map((entry) => summarizeAssignment(entry, trainingMap.get(entry.trainingId))),
      retraining: retraining.map((entry) => summarizeAssignment(entry, trainingMap.get(entry.trainingId))),
    });
  } catch (err) {
    console.error('[training/wk/reminders] error', err);
    return bad(res, 'server error', 500);
  }
}
