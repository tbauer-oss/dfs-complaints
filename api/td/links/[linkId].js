export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdLinkDelete } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;
  if (req.method !== 'DELETE') return bad(res, 'method not allowed', 405);
  try {
    await tdLinkDelete(String(req.query?.linkId || '').trim());
    return ok(res, { ok: true });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
