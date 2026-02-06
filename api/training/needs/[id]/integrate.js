// /api/training/needs/[id]/integrate.js – Integrate training need into program
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed, readJson } from '../../../_lib/http.js';
import { withCorsHandler } from '../../../_lib/http.js';
import { requireTrainingIntegrationAccess } from '../../../admin/_guard.js';
import { isAdminUser } from '../../../_lib/portalAuth.js';
import {
  trainingNeedGet,
  trainingNeedUpdate,
  trainingProgramGet,
  trainingProgramSave,
  trainingProgramUpdate,
  trainingProgramNeedLinksAll,
  trainingProgramNeedLinkSave,
} from '../../../_lib/store.js';
import { validateTrainingProgram } from '../../../_lib/trainingValidation.js';


function resolveNeedDepartment(need) {
  if (!need) return '';
  if (need.departmentTeamSelected === 'Sonstiges...') {
    return need.departmentTeamFreeText || '';
  }
  return need.departmentTeamSelected || need.department || '';
}

function parsePlannedParticipants(program) {
  if (!program) return null;
  const parsed = Number(String(program.participantsPlanned || '').trim().replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : null;
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
    const id = req.query?.id;
    if (!id) return bad(res, 'id missing', 400);
    const body = readJson(req) || {};
    const mode = body.mode === 'useExisting' ? 'useExisting' : 'create';
    const linkNeed = body.linkNeed !== false;
    const markNeedDone = body.markNeedDone === true;
    const mergeParticipants = body.mergeParticipants === true;
    const mergeBudget = body.mergeBudget === true;

    const need = await trainingNeedGet(id);
    if (!need) return bad(res, 'not found', 404);

    const links = await trainingProgramNeedLinksAll();
    const existingLink = links.find((entry) => entry.trainingNeedId === need.id);
    const existingSameLink =
      mode === 'useExisting' &&
      body.programEntryId &&
      links.find((entry) => entry.trainingNeedId === need.id && entry.programEntryId === body.programEntryId);
    if (existingSameLink) {
      return ok(res, { ok: true, programEntryId: existingSameLink.programEntryId, need });
    }
    if (existingLink) {
      return bad(res, 'already integrated', 409, { programEntryId: existingLink.programEntryId });
    }

    const item = Array.isArray(need.items) ? need.items[0] : null;
    const department = resolveNeedDepartment(need);
    let program = null;
    let link = null;

    if (mode === 'useExisting') {
      const programEntryId = body.programEntryId;
      if (!programEntryId) return bad(res, 'programEntryId missing', 400);
      program = await trainingProgramGet(programEntryId);
      if (!program) return bad(res, 'program not found', 404);
      if (linkNeed) {
        const noteLine = createSourceNote(need, department);
        const notes = program.notes ? `${program.notes}\n${noteLine}` : noteLine;
        const nextNeedIds = [...new Set([...(program.needIds || []), need.id])];
        const update = {
          notes,
          needIds: nextNeedIds,
        };
        if (mergeParticipants) {
          const current = parsePlannedParticipants(program);
          const add = Number(item?.participants || 0);
          if (current !== null && Number.isFinite(add)) {
            update.participantsPlanned = String(Math.max(0, current + add));
          }
        }
        if (mergeBudget && Number.isFinite(need.plannedBudget)) {
          update.budgetTotal = Number(program.budgetTotal || 0) + Number(need.plannedBudget || 0);
        }
        program = await trainingProgramUpdate(program.id, {
          ...update,
          updatedBy: actor.email,
        });
        link = await trainingProgramNeedLinkSave({
          programEntryId: program.id,
          trainingNeedId: need.id,
          linkedByUserId: actor.email,
        });
      }
    } else {
      const draft = buildProgramDraft({ need, actor, draft: body.programDraft || {} });
      if (linkNeed) draft.needIds = [need.id];
      const { errors } = validateTrainingProgram(draft);
      if (Object.keys(errors).length > 0) {
        return bad(res, 'Validierung fehlgeschlagen.', 400, { errors });
      }
      program = await trainingProgramSave({
        ...draft,
        createdBy: actor.email,
        updatedBy: actor.email,
      });
      if (linkNeed) {
        link = await trainingProgramNeedLinkSave({
          programEntryId: program.id,
          trainingNeedId: need.id,
          linkedByUserId: actor.email,
        });
      }
    }

    const updatedNeed = await trainingNeedUpdate(need.id, {
      status: markNeedDone ? 'closed' : 'integrated',
      integratedAt: Date.now(),
      integratedByUserId: actor.email,
      updatedBy: actor.email,
    });

    return ok(res, { ok: true, program, need: updatedNeed, link, linked: linkNeed });
  } catch (err) {
    console.error('[training/needs/integrate] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler);
