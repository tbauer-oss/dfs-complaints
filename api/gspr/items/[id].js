// /api/gspr/items/[id].js – Einzelne GSPR Items
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { gsprGet, gsprUpdate, gsprAddAuditEvent } from '../../_lib/store.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const wantsWrite = ['PATCH'].includes(req.method);
  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    if (req.method === 'GET') {
      const item = await gsprGet(id);
      if (!item) return bad(res, 'not found', 404);
      return ok(res, { ok: true, item });
    }

    if (req.method === 'PATCH') {
      const current = await gsprGet(id);
      if (!current) return bad(res, 'not found', 404);
      if (current.status === 'APPROVED') {
        return bad(res, 'approved items are read-only', 409);
      }
      const body = readJson(req) || {};
      const payload = {
        ...body,
        status: current.status,
        approvedAt: current.approvedAt,
        approvedBy: current.approvedBy,
        updatedBy: actor.email,
      };
      const updated = await gsprUpdate(id, payload);
      if (!updated) return bad(res, 'not found', 404);
      await gsprAddAuditEvent(id, {
        gsprItemId: id,
        timestamp: Date.now(),
        actorUserId: actor.email,
        actorName: actor.displayName || actor.email,
        action: 'EDIT',
        fromStatus: current.status,
        toStatus: updated.status,
        comment: '',
      });
      return ok(res, { ok: true, item: updated });
    }

    return methodNotAllowed(res);
  } catch (err) {
    console.error('[gspr/items/id] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
