// /api/gspr/chapter.js – GSPR chapter data for TD
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import {
  fmeaGet,
  gsprAssessmentsByTdAndChapter,
  gsprEnsureAssessmentsForTd,
  gsprTdSignoffGet,
} from '../_lib/store.js';
import { gsprItemsByChapter } from '../_lib/gsprRequirements.js';

const GSPR_TILE = 'gspr';

function parseChapter(value) {
  const v = (value || '').toString().trim().toUpperCase();
  if (v === 'I' || v === '1') return 1;
  if (v === 'II' || v === '2') return 2;
  if (v === 'III' || v === '3') return 3;
  return null;
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false, allowPrrc: true });
  if (!actor) return;

  try {
    if (req.method !== 'GET') return bad(res, 'method not allowed', 405);
    const tdId = (req.query?.tdId || '').toString();
    if (!tdId) return bad(res, 'tdId missing', 400);
    const chapter = parseChapter(req.query?.chapter);
    if (!chapter) return bad(res, 'invalid chapter', 400);

    const td = await fmeaGet(tdId);
    if (!td) return bad(res, 'td not found', 404);

    const signoff = await gsprTdSignoffGet(tdId);
    await gsprEnsureAssessmentsForTd(tdId, { status: signoff.status, actor });
    const assessments = await gsprAssessmentsByTdAndChapter(tdId, chapter);
    const assessmentByRequirement = new Map(assessments.map((a) => [a.requirementId, a]));

    const requirements = gsprItemsByChapter(chapter);
    const items = requirements.map((requirement) => {
      const assessment = assessmentByRequirement.get(requirement.id);
      return {
        requirement,
        assessment: assessment || null,
      };
    });

    const readOnly = td.active === false || Boolean(td.archivedAt) || signoff.status === 'approved';

    return ok(res, {
      ok: true,
      tdId,
      status: signoff.status,
      submittedAt: signoff.submittedAt,
      submittedBy: signoff.submittedBy,
      approvedAt: signoff.approvedAt,
      approvedBy: signoff.approvedBy,
      items,
      readOnly,
      td: {
        id: td.id,
        mdrTd: td.mdrTd,
        title: td.title,
        productGroup: td.productGroup,
        medicalProduct: td.medicalProduct,
        active: td.active !== false,
        archivedAt: td.archivedAt || null,
      },
    });
  } catch (err) {
    console.error('[gspr/chapter] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
