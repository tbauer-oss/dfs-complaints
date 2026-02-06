// /api/training/needs/integrate-bulk.js – Bulk integration for training needs
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { withCorsHandler } from '../../_lib/http.js';
import { requireTrainingIntegrationAccess } from '../../admin/_guard.js';
import { isAdminUser } from '../../_lib/portalAuth.js';
import {
  trainingNeedsAll,
  trainingNeedUpdate,
  trainingProgramSave,
  trainingProgramNeedLinksAll,
  trainingProgramNeedLinkSave,
} from '../../_lib/store.js';
import { validateTrainingProgram } from '../../_lib/trainingValidation.js';


function resolveNeedDepartment(need) {
  if (!need) return '';
  if (need.departmentTeamSelected === 'Sonstiges...') {
    return need.departmentTeamFreeText || '';
  }
  return need.departmentTeamSelected || need.department || '';
}

function createSourceNote(need, department) {
  const date = new Date().toLocaleDateString('de-DE');
  return `Quelle Schulungsbedarf: ${need.id} / ${department || '—'} / ${date}`;
}

function buildProgramDraft({ need, actor, draft = {} }) {
  const item = Array.isArray(need.items) ? need.items[0] : null;
  const department = resolveNeedDepartment(need);
  const plannedBudget = Number.isFinite(need.plannedBudget) ? need.plannedBudget : null;
  return {
    year: Number(draft.year || need.year),
    title: draft.title || item?.topic || '',
    category: draft.category || 'other',
    categoryFreeText: draft.categoryFreeText || null,
    plannedPeriodType: draft.plannedPeriodType || need.plannedPeriodType,
    plannedPeriodValue: draft.plannedPeriodValue || need.plannedPeriodValue,
    format: draft.format || need.trainingFormat,
    intervalType: draft.intervalType || need.intervalType || 'once',
    intervalValue: draft.intervalValue || need.intervalValue || null,
    responsiblePerson: draft.responsiblePerson || actor.email,
    owner: draft.owner || actor.email,
    department: draft.department || department,
    targetGroup: draft.targetGroup || department,
    participantsPlanned:
      draft.participantsPlanned ||
      String(item?.participants ?? '').trim() ||
      '1',
    trainerProvider: draft.trainerProvider || '',
    location: draft.location || '',
    duration: draft.duration || '',
    notes: draft.notes || need.additionalNotes || need.comments || '',
    status: draft.status || 'planned',
    budgetTotal: Number.isFinite(draft.budgetTotal)
      ? Number(draft.budgetTotal)
      : plannedBudget ?? 0,
    needIds: Array.isArray(draft.needIds) ? draft.needIds : [],
    trainingIds: Array.isArray(draft.trainingIds) ? draft.trainingIds : [],
  };
}

async function handler(req, res) {
  if (req.method === 'OPTIONS') return res.status(204).end();
  const actor = await requireTrainingIntegrationAccess(req, res);
  if (!actor) return;
  if (!isAdminUser(actor)) return bad(res, 'forbidden', 403);

  try {
    if (req.method !== 'POST') return methodNotAllowed(res);
    const body = readJson(req) || {};
    const needIds = Array.isArray(body.needIds) ? body.needIds.map(String) : [];
    if (needIds.length == 0) return bad(res, 'needIds missing', 400);
    const bulkMode = body.bulkMode === 'oneToOne' ? 'oneToOne' : 'grouped';
    const markNeedsDone = body.markNeedsDone === true;
    const linkNeed = body.linkNeed !== false;

    const needs = (await trainingNeedsAll()).filter((entry) => needIds.includes(entry.id));
    if (needs.length !== needIds.length) {
      return bad(res, 'missing needs', 404);
    }

    const links = await trainingProgramNeedLinksAll();
    const alreadyLinked = needs.filter((need) => links.some((link) => link.trainingNeedId === need.id));
    if (alreadyLinked.length > 0) {
      return bad(res, 'already integrated', 409, { needIds: alreadyLinked.map((need) => need.id) });
    }

    const createdPrograms = [];
    const createdLinks = [];
    const updatedNeeds = [];

    if (bulkMode === 'grouped') {
      const base = needs[0];
      const draft = buildProgramDraft({ need: base, actor, draft: body.programDraft || {} });
      if (!body.programDraft?.participantsPlanned) {
        const total = needs.reduce((sum, entry) => {
          const item = Array.isArray(entry.items) ? entry.items[0] : null;
          return sum + Number(item?.participants || 0);
        }, 0);
        draft.participantsPlanned = total > 0 ? String(total) : draft.participantsPlanned;
      }
      const noteLines = needs.map((need) => createSourceNote(need, resolveNeedDepartment(need)));
      draft.notes = draft.notes ? `${draft.notes}\n${noteLines.join('\n')}` : noteLines.join('\n');
      if (linkNeed) draft.needIds = needIds;
      const { errors } = validateTrainingProgram(draft);
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      const program = await trainingProgramSave({
        ...draft,
        createdBy: actor.email,
        updatedBy: actor.email,
      });
      createdPrograms.push(program);
      if (linkNeed) {
        for (const need of needs) {
          const link = await trainingProgramNeedLinkSave({
            programEntryId: program.id,
            trainingNeedId: need.id,
            linkedByUserId: actor.email,
          });
          if (link) createdLinks.push(link);
        }
      }
    } else {
      for (const need of needs) {
        const draft = buildProgramDraft({ need, actor, draft: body.programDraft || {} });
        if (linkNeed) draft.needIds = [need.id];
        const { errors } = validateTrainingProgram(draft);
        if (Object.keys(errors).length > 0) {
          return bad(res, 'Validierung fehlgeschlagen.', 400, { errors, needId: need.id });
        }
        const program = await trainingProgramSave({
          ...draft,
          createdBy: actor.email,
          updatedBy: actor.email,
        });
        createdPrograms.push(program);
        if (linkNeed) {
          const link = await trainingProgramNeedLinkSave({
            programEntryId: program.id,
            trainingNeedId: need.id,
            linkedByUserId: actor.email,
          });
          if (link) createdLinks.push(link);
        }
      }
    }

    for (const need of needs) {
      const updated = await trainingNeedUpdate(need.id, {
        status: markNeedsDone ? 'closed' : 'integrated',
        integratedAt: Date.now(),
        integratedByUserId: actor.email,
        updatedBy: actor.email,
      });
      if (updated) updatedNeeds.push(updated);
    }

    return ok(res, { ok: true, programs: createdPrograms, needs: updatedNeeds, links: createdLinks });
  } catch (err) {
    console.error('[training/needs/integrate-bulk] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler);
