// /api/gspr/items/[id]/workflow.js – Workflow Aktionen
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { gsprGet, gsprWorkflowAction } from '../../../_lib/store.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: true, allowPrrc: true });
  if (!actor) return;

  if (req.method !== 'POST') return methodNotAllowed(res);

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);
    const item = await gsprGet(id);
    if (!item) return bad(res, 'not found', 404);

    const body = readJson(req) || {};
    const action = (body.action || '').toString();
    const comment = (body.comment || '').toString();
    const reason = (body.reason || '').toString();

    const role = (actor.role || '').toString().toLowerCase();
    const isAdmin = role === 'admin' || role === 'superuser';
    const isQm = actor.isQM === true || role === 'qm';
    const isPrrc = actor.isPRRC === true;

    if (action === 'submit_to_qm_review' && !(isQm || isAdmin)) return bad(res, 'forbidden', 403);
    if (action === 'submit_to_prrc_review' && !(isQm || isAdmin)) return bad(res, 'forbidden', 403);
    if (action === 'approve' && !(isPrrc || isAdmin)) return bad(res, 'forbidden', 403);
    if (action === 'request_change' && !(isQm || isAdmin)) return bad(res, 'forbidden', 403);
    if (action === 'return_to_draft') {
      if (item.status === 'QM_REVIEW' && !(isQm || isAdmin)) return bad(res, 'forbidden', 403);
      if (item.status === 'PRRC_REVIEW' && !(isPrrc || isAdmin)) return bad(res, 'forbidden', 403);
    }

    if (action === 'return_to_draft' && !comment.trim()) {
      return bad(res, 'comment required', 400);
    }
    if (action === 'request_change' && !reason.trim()) {
      return bad(res, 'reason required', 400);
    }

    if (action === 'submit_to_qm_review' && item.status !== 'DRAFT') {
      return bad(res, 'invalid status', 409);
    }
    if (action === 'submit_to_prrc_review' && item.status !== 'QM_REVIEW') {
      return bad(res, 'invalid status', 409);
    }
    if (action === 'approve' && item.status !== 'PRRC_REVIEW') {
      return bad(res, 'invalid status', 409);
    }
    if (action === 'return_to_draft' && !['QM_REVIEW', 'PRRC_REVIEW'].includes(item.status)) {
      return bad(res, 'invalid status', 409);
    }
    if (action === 'request_change' && item.status !== 'APPROVED') {
      return bad(res, 'invalid status', 409);
    }

    const updated = await gsprWorkflowAction(id, {
      action,
      actor,
      comment: comment.trim(),
      reason: reason.trim(),
    });
    if (!updated) return bad(res, 'not found', 404);
    return ok(res, { ok: true, item: updated });
  } catch (err) {
    const msg = err?.message || 'server error';
    const status = msg.includes('justification') ? 400 : 500;
    console.error('[gspr/workflow] error', err);
    return bad(res, msg, status);
  }
}
