// /api/training/wk/reminders – Due/overdue Wirksamkeitskontrollen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import { trainingRecordsAll } from '../../_lib/store.js';

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

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const now = Date.now();
    const list = await trainingRecordsAll();
    const isAdmin = isAdminUser(actor);
    const filtered = list.filter((training) => {
      if (!training.wkMethod || !training.wkDueAt || training.wkStatus === 'done') return false;
      if (isAdmin) return true;
      const responsible = (training.wkResponsibleId || '').toString().toLowerCase();
      return responsible && responsible === (actor.email || '').toString().toLowerCase();
    });

    const dueSoon = filtered.filter((training) => training.wkDueAt >= now && training.wkDueAt <= now + 14 * 24 * 60 * 60 * 1000);
    const overdue = filtered.filter((training) => training.wkDueAt < now);

    return ok(res, {
      ok: true,
      dueSoon: dueSoon.map(summarizeTraining),
      overdue: overdue.map(summarizeTraining),
    });
  } catch (err) {
    console.error('[training/wk/reminders] error', err);
    return bad(res, 'server error', 500);
  }
}
