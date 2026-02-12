export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdChangeGet, tdChangePatch } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const changeId = String(req.query?.changeId || '').trim();
  if (!changeId) return bad(res, 'changeId is required', 400);
  const wantsWrite = req.method === 'PATCH';
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: wantsWrite });
  if (!actor) return;
  try {
    if (req.method === 'GET') {
      const item = await tdChangeGet(changeId);
      if (!item) return bad(res, 'not found', 404);
      return ok(res, { ok: true, item });
    }
    if (req.method === 'PATCH') {
      return ok(res, { ok: true, item: await tdChangePatch(changeId, readJson(req), actor.email || actor.id || null) });
    }
    return bad(res, 'method not allowed', 405);
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
