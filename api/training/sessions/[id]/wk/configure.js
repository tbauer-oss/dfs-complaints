// /api/training/sessions/[id]/wk/configure – Configure Wirksamkeitskontrolle
export const config = { runtime: 'nodejs' };

import { ok, bad, methodNotAllowed, readJson } from '../../../../_lib/http.js';
import { withCorsHandler } from '../../../../_lib/http.js';
import { requireTrainingScopeAccess } from '../../../../admin/_guard.js';
import { isAdminUser } from '../../../../_lib/portalAuth.js';
import { trainingRecordGet, trainingRecordUpdate, trainingTemplateGet } from '../../../../_lib/store.js';

const TRAINING_TILE = 'trainingEffectiveness';
const WK_METHODS = new Set(['questionnaire', 'direct', 'indirect']);

async function handler(req, res) {
  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await requireTrainingScopeAccess(req, res, { tile: TRAINING_TILE, write: true });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'missing id', 400);

    const training = await trainingRecordGet(id);
    if (!training) return bad(res, 'not found', 404);

    const body = readJson(req) || {};
    const method = (body.wkMethod || '').toString();
    if (!WK_METHODS.has(method)) return bad(res, 'invalid wkMethod', 400);

    const delayDays = Number(body.wkDelayDays || 0);
    if (!Number.isFinite(delayDays) || delayDays <= 0) return bad(res, 'wkDelayDays required', 400);

    if (method === 'questionnaire' && !(body.wkQuestionnaireTemplateId || body.questionnaireTemplateId)) {
      return bad(res, 'questionnaireTemplateId required', 400);
    }

    let wkThresholdPercent = Number(body.wkThresholdPercent ?? body.thresholdPercent ?? 0);
    if (method === 'questionnaire') {
      const templateId = (body.wkQuestionnaireTemplateId || body.questionnaireTemplateId || '').toString();
      const template = await trainingTemplateGet(templateId);
      const defaultThreshold = Number(template?.defaultThresholdPercent ?? 70);
      if (!wkThresholdPercent && wkThresholdPercent !== 0) wkThresholdPercent = defaultThreshold;
      if (!Number.isFinite(wkThresholdPercent) || wkThresholdPercent < 0 || wkThresholdPercent > 100) {
        return bad(res, 'wkThresholdPercent invalid', 400);
      }
    }

    const updated = await trainingRecordUpdate(training.id, {
      wkMethod: method,
      wkDelayDays: delayDays,
      wkResponsibleId: (body.wkResponsibleId || actor.email || '').toString(),
      wkQuestionnaireTemplateId: (body.wkQuestionnaireTemplateId || body.questionnaireTemplateId || '').toString(),
      wkThresholdPercent: wkThresholdPercent || null,
      wkTargetParticipantIds: Array.isArray(body.wkTargetParticipantIds)
        ? body.wkTargetParticipantIds.map((entry) => entry.toString())
        : [],
      updatedBy: actor.email,
      auditLog: [
        ...(training.auditLog || []),
        { action: 'wk_config', message: 'Wirksamkeitskontrolle konfiguriert', by: actor.email, at: Date.now() },
      ],
    });

    if (!updated) return bad(res, 'not found', 404);
    if (!isAdminUser(actor) && training.completedAt && !updated.wkMethod) {
      return bad(res, 'wk method required after completion', 400);
    }
    return ok(res, { ok: true, record: updated });
  } catch (err) {
    console.error('[training/wk/configure] error', err);
    return bad(res, 'server error', 500);
  }
}

export default withCorsHandler(handler);
