export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { tdSectionByTd } from '../../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdKey = String(req.query?.tdKey || '').trim();
  const sectionId = String(req.query?.sectionId || '').trim();
  if (!tdKey || !sectionId) return bad(res, 'tdKey and sectionId are required', 400);

  const started = Date.now();
  try {
    const item = await tdSectionByTd(tdKey, sectionId);
    if (!item) return bad(res, 'not found', 404);
    console.info('[td/section]', { td_key: tdKey, section_id: sectionId, total_ms: Date.now() - started });
    return ok(res, { ok: true, item });
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
