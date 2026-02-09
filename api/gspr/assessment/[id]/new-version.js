// /api/gspr/assessment/[id]/new-version.js – Create new version
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { gsprAssessmentGet, gsprAssessmentNewVersion, gsprTdSignoffSave } from '../../../_lib/store.js';
import { GSPR_ITEMS_BY_ID } from '../../../_lib/gsprRequirements.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: true, allowPrrc: true });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    if (req.method !== 'POST') return bad(res, 'method not allowed', 405);

    const current = await gsprAssessmentGet(id);
    if (!current) return bad(res, 'not found', 404);
    const requirement = GSPR_ITEMS_BY_ID.get(current.requirementId);
    if (!requirement?.isAssessable) {
      return bad(res, 'requirement is not assessable', 400);
    }

    const updated = await gsprAssessmentNewVersion(id, actor);
    await gsprTdSignoffSave(current.tdId, {
      status: 'draft',
      approvedAt: null,
      approvedBy: '',
      approvedHash: '',
      submittedAt: null,
      submittedBy: '',
    });

    return ok(res, { ok: true, assessment: updated });
  } catch (err) {
    console.error('[gspr/assessment/new-version] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
