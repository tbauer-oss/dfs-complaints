export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, readJson } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdGet, tdUpdate, tdDelete, tdSections, tdLinks, tdComputedSummary, tdReadiness } from '../_lib/tdStore.js';

const TD_TILE = 'td';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const id = String(req.query?.id || '').trim();
  if (!id) return bad(res, 'id is required', 400);

  const wantsWrite = req.method !== 'GET';
  const actor = await requirePortalAccess(req, res, { tile: TD_TILE, write: wantsWrite });
  if (!actor) return;

  try {
    if (req.method === 'GET' && id === 'readiness') {
      const tdId = String(req.query?.tdId || '').trim();
      if (!tdId) return bad(res, 'tdId is required', 400);
      return ok(res, { ok: true, ...(await tdReadiness(tdId)) });
    }

    if (req.method === 'GET') {
      const td = await tdGet(id);
      if (!td || td.deletedAt) return bad(res, 'not found', 404);
      const [sections, links, summary] = await Promise.all([tdSections(id), tdLinks(id), tdComputedSummary(td)]);
      return ok(res, { ok: true, item: td, sections, links, summary });
    }
    if (req.method === 'PATCH') {
      const item = await tdUpdate(id, readJson(req));
      return ok(res, { ok: true, item });
    }
    if (req.method === 'DELETE') {
      const item = await tdDelete(id);
      return ok(res, { ok: true, item });
    }
    return bad(res, 'method not allowed', 405);
  } catch (err) {
    return bad(res, err?.message || 'server error', 500);
  }
}
