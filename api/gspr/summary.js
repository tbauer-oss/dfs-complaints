// /api/gspr/summary.js – GSPR summary per TD
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  fmeaGet,
  gsprAssessmentsByTd,
  gsprAssessmentHasContent,
  gsprEnsureAssessmentsForTd,
  gsprTdSignoffGet,
} from '../_lib/store.js';
import { gsprAssessableItemsByChapter } from '../_lib/gsprRequirements.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
    const tdId = (req.query?.tdId || '').toString();
    if (!tdId) return bad(res, 'tdId missing', 400);

    const td = await fmeaGet(tdId);
    if (!td) return bad(res, 'td not found', 404);

    const signoff = await gsprTdSignoffGet(tdId);
    await gsprEnsureAssessmentsForTd(tdId, { status: signoff.status, actor });
    const assessments = await gsprAssessmentsByTd(tdId);
    const assessmentByRequirement = new Map(assessments.map((a) => [a.requirementId, a]));

    const chapters = [1, 2, 3].map((chapter) => {
      const requirements = gsprAssessableItemsByChapter(chapter);
      const total = requirements.length;
      let assessed = 0;
      let notApplicable = 0;
      for (const requirement of requirements) {
        const assessment = assessmentByRequirement.get(requirement.id);
        if (!assessment) continue;
        if (assessment.status === 'not_applicable') notApplicable += 1;
        if (gsprAssessmentHasContent(assessment)) {
          assessed += 1;
        }
      }
      return { chapter, total, assessed, notApplicable };
    });

    const readOnly = td.active === false || Boolean(td.archivedAt);

    return ok(res, {
      ok: true,
      tdId,
      status: signoff.status,
      submittedAt: signoff.submittedAt,
      submittedBy: signoff.submittedBy,
      approvedAt: signoff.approvedAt,
      approvedBy: signoff.approvedBy,
      chapters,
      readOnly,
    });
  } catch (err) {
    console.error('[gspr/summary] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
