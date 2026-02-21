export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { gsprAssessmentsByTd, gsprEnsureAssessmentsForTd, gsprSourceMetaGet, gsprTdSignoffGet } from '../../../_lib/store.js';
import { gsprAssessableItemsByChapter } from '../../../_lib/gsprRequirements.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'gspr', write: false, allowPrrc: true });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdId = String(req.query?.tdId || '').trim();
  if (!tdId) return bad(res, 'tdId is required', 400);

  const signoff = await gsprTdSignoffGet(tdId);
  await gsprEnsureAssessmentsForTd(tdId, { status: signoff.status, actor });
  const [assessments, sourceMeta] = await Promise.all([gsprAssessmentsByTd(tdId), gsprSourceMetaGet()]);
  const byReq = new Map(assessments.map((a) => [a.requirementId, a]));

  const chapters = [1, 2, 3].map((chapter) => {
    const requirements = gsprAssessableItemsByChapter(chapter);
    let done = 0;
    for (const finalReq of requirements) {
      const item = byReq.get(finalReq.id);
      if (item && (item.status === 'compliant' || item.status === 'not_applicable')) done += 1;
    }
    const total = requirements.length;
    return {
      chapter,
      total,
      completed: done,
      completion: total > 0 ? Math.round((done / total) * 100) : 0,
      updatedAt: assessments[0]?.updatedAt || null,
    };
  });

  return ok(res, {
    ok: true,
    tdId,
    versionLabel: sourceMeta?.versionLabel || sourceMeta?.parserVersion || 'mdr-2017-745',
    versionHash: sourceMeta?.versionHash || sourceMeta?.lastGoodSyncAt || '',
    source: sourceMeta?.name || 'Regulatory Cache',
    chapters,
  });
}
