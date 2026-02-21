export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { gsprAssessmentsByTd, gsprEnsureAssessmentsForTd, gsprSourceMetaGet, gsprTdSignoffGet } from '../_lib/store.js';
import { GSPR_REQUIREMENTS_BY_ID } from '../_lib/gsprRequirements.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'gspr', write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdId = String(req.query?.tdId || '').trim();
  const gsprNo = String(req.query?.gsprNo || '').trim();
  if (!tdId || !gsprNo) return bad(res, 'tdId and gsprNo are required', 400);

  const signoff = await gsprTdSignoffGet(tdId);
  await gsprEnsureAssessmentsForTd(tdId, { status: signoff.status, actor });

  const [assessments, sourceMeta] = await Promise.all([gsprAssessmentsByTd(tdId), gsprSourceMetaGet()]);
  const requirement = GSPR_REQUIREMENTS_BY_ID[gsprNo];
  if (!requirement) return bad(res, 'requirement not found', 404);
  const assessment = assessments.find((entry) => entry.requirementId === gsprNo);

  return ok(res, {
    ok: true,
    tdId,
    gsprNo,
    versionLabel: sourceMeta?.versionLabel || sourceMeta?.parserVersion || 'mdr-2017-745',
    versionHash: sourceMeta?.versionHash || sourceMeta?.lastGoodSyncAt || '',
    source: sourceMeta?.name || 'Regulatory Cache',
    item: {
      gsprNo,
      title: requirement.title || gsprNo,
      text: requirement.fullText || '',
      status: assessment?.status || 'not_assessed',
      mapping: assessment?.rationale || '',
      evidenceLinks: assessment?.evidence || [],
      updatedAt: assessment?.updatedAt || null,
    },
  });
}
