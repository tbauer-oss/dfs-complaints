// /api/gspr/td/[tdId]/approve.js – PRRC approval
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import {
  fmeaGet,
  gsprAssessmentsByTd,
  gsprEnsureAssessmentsForTd,
  gsprTdApprovedHash,
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

    if (actor.isPRRC !== true) {
      return bad(res, 'forbidden', 403);
    }

    const td = await fmeaGet(tdId);
    if (!td) return bad(res, 'td not found', 404);

    await gsprEnsureAssessmentsForTd(tdId, { status: 'in_review', actor });
    const assessments = await gsprAssessmentsByTd(tdId);

    const approvedHash = gsprTdApprovedHash(assessments);
    const signoff = await gsprTdSignoffSave(tdId, {
      status: 'approved',
      approvedAt: new Date().toISOString(),
      approvedBy: actor.email || actor.id || '',
      approvedHash,
    });

    return ok(res, { ok: true, signoff });
  } catch (err) {
    console.error('[gspr/td/approve] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
