// /api/training/sessions/[id]/wk/complete – Complete Wirksamkeitskontrolle
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { isAdminUser } from '../../../_lib/portalAuth.js';
import {
  trainingRecordGet,
  trainingRecordUpdate,
  trainingWkAssessmentSave,
} from '../../../_lib/store.js';

const TRAINING_TILE = 'trainings';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'missing id', 400);

    const training = await trainingRecordGet(id);
    if (!training) return bad(res, 'not found', 404);

    const body = readJson(req) || {};
    const admin = isAdminUser(actor);
    const actorMail = (actor.email || '').toString().toLowerCase();
    const responsible = (training.wkResponsibleId || '').toString().toLowerCase();
    if (!admin && (!responsible || responsible !== actorMail)) {
      return bad(res, 'forbidden', 403);
    }

    const now = Date.now();
    let assessmentId = null;
    const method = (training.wkMethod || '').toString();
    if (!method) return bad(res, 'wk method missing', 400);

    if (method === 'direct' || method === 'indirect') {
      const result = (body.result || '').toString();
      if (!result) return bad(res, 'result required', 400);
      const assessment = await trainingWkAssessmentSave({
        trainingSessionId: training.id,
        assessmentType: method,
        performedAt: Number(body.performedAt || now),
        performedByUserId: actor.email || '',
        result,
        notes: (body.notes || '').toString(),
        attachments: Array.isArray(body.attachments) ? body.attachments : [],
        createdBy: actor.email,
        updatedBy: actor.email,
      });
      assessmentId = assessment.id;
    } else if (method === 'questionnaire') {
      if (body.override !== true) {
        return bad(res, 'questionnaire completion requires override', 400);
      }
      if (!admin) return bad(res, 'forbidden', 403);
      const reason = (body.reason || '').toString().trim();
      if (reason.length < 5) return bad(res, 'reason required', 400);
    }

    const updated = await trainingRecordUpdate(training.id, {
      wkStatus: 'done',
      wkCompletedAt: now,
      updatedBy: actor.email,
      auditLog: [
        ...(training.auditLog || []),
        {
          action: 'wk_complete',
          message: assessmentId ? 'Wirksamkeitskontrolle abgeschlossen' : 'Wirksamkeitskontrolle abgeschlossen (Override)',
          by: actor.email,
          at: now,
        },
      ],
    });

    return ok(res, { ok: true, record: updated, assessmentId });
  } catch (err) {
    console.error('[training/wk/complete] error', err);
    return bad(res, 'server error', 500);
  }
}
