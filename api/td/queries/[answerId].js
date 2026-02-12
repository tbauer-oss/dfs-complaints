export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdQueryUpdate } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;
  if (req.method !== 'PUT') return bad(res, 'method not allowed', 405);
  const answerId = String(req.query?.answerId || '').trim();
  if (!answerId) return bad(res, 'answerId is required', 400);
  try {
    return ok(res, { ok: true, item: await tdQueryUpdate(answerId, readJson(req), actor.email || actor.id || null) });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
