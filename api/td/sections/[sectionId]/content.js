export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad, readJson } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { tdSectionContentPut } from '../../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  if (req.method !== 'PUT') return bad(res, 'method not allowed', 405);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;
  const sectionId = String(req.query?.sectionId || '').trim();
  if (!sectionId) return bad(res, 'sectionId is required', 400);
  try {
    const item = await tdSectionContentPut(sectionId, readJson(req), actor.email || actor.id || null);
    return ok(res, { ok: true, item });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
