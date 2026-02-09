// /api/gspr/assessment/[id].js – Update GSPR assessment
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { gsprAssessmentGet, gsprAssessmentUpdate, gsprTdSignoffGet } from '../../_lib/store.js';
import { GSPR_ITEMS_BY_ID } from '../../_lib/gsprRequirements.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['PUT'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: wantsWrite, allowPrrc: true });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    if (req.method === 'PUT') {
      const body = readJson(req) || {};
      const current = await gsprAssessmentGet(id);
      if (!current) return bad(res, 'not found', 404);
      const requirement = GSPR_ITEMS_BY_ID.get(current.requirementId);
      if (!requirement?.isAssessable) {
        return bad(res, 'requirement is not assessable', 400);
      }

      if (body.tdId && body.tdId !== current.tdId) {
        return bad(res, 'tdId mismatch', 400);
      }

      const signoff = await gsprTdSignoffGet(current.tdId);
      if (signoff?.status === 'approved') {
        return bad(res, 'td approved; create new version', 409);
      }

      const patch = {
        status: body.status,
        rationale: body.rationale,
        evidence: body.evidence,
        owner: body.owner,
        dueDate: body.dueDate,
        applicable: body.applicable,
        standards: body.standards,
        edition: body.edition,
        supportingDocs: body.supportingDocs,
        revision: body.revision,
        date: body.date,
        comments: body.comments,
        additionalDataRequired: body.additionalDataRequired,
      };

      if (['not_applicable', 'partial', 'not_fulfilled'].includes(String(body.status))) {
        if (!String(body.rationale || '').trim()) {
          return bad(res, 'rationale required for selected status', 400);
        }
      }

      const updated = await gsprAssessmentUpdate(id, patch, actor);
      return ok(res, { ok: true, assessment: updated });
    }

    return bad(res, 'method not allowed', 405);
  } catch (err) {
    console.error('[gspr/assessment/id] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
