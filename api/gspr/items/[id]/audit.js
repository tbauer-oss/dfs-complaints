// /api/gspr/items/[id]/audit.js – Audit Trail
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { gsprAuditList } from '../../../_lib/store.js';

const GSPR_TILE = 'gspr';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: GSPR_TILE, write: false, allowPrrc: true });
  if (!actor) return;

  if (req.method !== 'GET') return methodNotAllowed(res);

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);
    const events = await gsprAuditList(id);
    return ok(res, { ok: true, events });
  } catch (err) {
    console.error('[gspr/audit] error', err);
    return bad(res, err?.message || 'server error', 500);
  }
}
