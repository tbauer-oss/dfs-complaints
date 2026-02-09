// /api/gspr/td/[tdId]/submit.js – Submit GSPR TD for review
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import {
  fmeaGet,
  gsprAssessmentHasContent,
  gsprAssessmentsByTd,
  gsprEnsureAssessmentsForTd,
  gsprTdSignoffSave,
} from '../../../_lib/store.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: true, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method !== 'POST') return bad(res, 'method not allowed', 405);
    const tdId = (req.query?.tdId || '').toString();
    if (!tdId) return bad(res, 'tdId missing', 400);

    const td = await fmeaGet(tdId);
    if (!td) return bad(res, 'td not found', 404);

    await gsprEnsureAssessmentsForTd(tdId, { status: 'draft', actor });
    const assessments = await gsprAssessmentsByTd(tdId);

    const invalid = assessments.filter((assessment) => !gsprAssessmentHasContent(assessment));

    if (invalid.length > 0) {
      return bad(res, 'not all applicable requirements are filled', 400, {
        missingRequirementIds: invalid.map((i) => i.requirementId),
      });
    }

    const signoff = await gsprTdSignoffSave(tdId, {
      status: 'in_review',
      submittedAt: new Date().toISOString(),
      submittedBy: actor.email || actor.id || '',
      approvedAt: null,
      approvedBy: '',
      approvedHash: '',
    });

    return ok(res, { ok: true, signoff });
  } catch (err) {
    console.error('[gspr/td/submit] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
