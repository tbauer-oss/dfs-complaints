export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { tdBootstrapQueries } from '../../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;
  if (req.method !== 'POST') return bad(res, 'method not allowed', 405);
  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);
  try {
    return ok(res, { ok: true, ...(await tdBootstrapQueries(id, actor.email || actor.id || null)) });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
