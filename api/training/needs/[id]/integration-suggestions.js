// /api/training/needs/[id]/integration-suggestions.js – Suggestions for training program integration
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed } from '../../../_lib/http.js';
import { withCors } from '../../../_lib/withCors.ts';
import { requireTrainingIntegrationAccess } from '../../../admin/_guard.js';
import { isAdminUser } from '../../../_lib/portalAuth.js';
import { trainingNeedGet, trainingProgramsAll } from '../../../_lib/store.js';


function normalizeText(value) {
  return String(value || '').trim().toLowerCase();
}

function resolveNeedDepartment(need) {
  if (!need) return '';
  if (need.departmentTeamSelected === 'Sonstiges...') {
    return need.departmentTeamFreeText || '';
  }
  return need.departmentTeamSelected || need.department || '';
}

async function handler(req, res) {
  const actor = await requireTrainingIntegrationAccess(req, res);
  if (!actor) return;
  if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);

  try {
    if (req.method !== 'GET') return methodNotAllowed(res);
    const id = req.query?.id;
    if (!id) return bad(res, 'id missing', 400);
    const need = await trainingNeedGet(id);
    if (!need) return bad(res, 'not found', 404);

    const programs = await trainingProgramsAll();
    const primaryItem = Array.isArray(need.items) ? need.items[0] : null;
    const titleKey = normalizeText(primaryItem?.topic || '');
    const dept = normalizeText(resolveNeedDepartment(need));
    const format = normalizeText(need.trainingFormat);
    const intervalType = normalizeText(need.intervalType);
    const intervalValue = normalizeText(need.intervalValue || '');
    const plannedPeriodValue = need.plannedPeriodValue || '';

    const matches = programs.filter((program) => {
      if (program.year !== need.year) return false;
      if (titleKey && normalizeText(program.title) !== titleKey) return false;
      if (format && normalizeText(program.format) !== format) return false;
      if (plannedPeriodValue && program.plannedPeriodValue !== plannedPeriodValue) return false;
      if (intervalType && normalizeText(program.intervalType) !== intervalType) return false;
      if (intervalValue && normalizeText(program.intervalValue || '') !== intervalValue) return false;
      if (dept && normalizeText(program.department) !== dept) return false;
      return true;
    });

    return ok(res, { ok: true, list: matches });
  } catch (err) {
    console.error('[training/needs/integration-suggestions] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCors(handler);
