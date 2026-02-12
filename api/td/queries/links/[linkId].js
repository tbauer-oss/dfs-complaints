export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { tdQueryLinkDelete } from '../../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;
  if (req.method !== 'DELETE') return bad(res, 'method not allowed', 405);
  const linkId = String(req.query?.linkId || '').trim();
  if (!linkId) return bad(res, 'linkId is required', 400);
  try {
    return ok(res, { ok: true, item: await tdQueryLinkDelete(linkId) });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
