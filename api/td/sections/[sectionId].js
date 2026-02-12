export const config = { runtime: 'nodejs' };
import { handlePreflight, setCors, ok, bad, readJson } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { tdSectionUpdate } from '../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);
  const actor = await requirePortalAccess(req, res, { tile: 'td', write: true });
  if (!actor) return;
  if (req.method !== 'PATCH') return bad(res, 'method not allowed', 405);
  try {
    const sectionId = String(req.query?.sectionId || '').trim();
    const item = await tdSectionUpdate(sectionId, readJson(req));
    return ok(res, { ok: true, item });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
