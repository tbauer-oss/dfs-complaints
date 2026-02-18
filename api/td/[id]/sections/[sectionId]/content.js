export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../../../../_lib/http.js';
import { requirePortalAccess } from '../../../../../admin/_guard.js';
import { withTiming } from '../../../../../_lib/timing.js';
import { tdSectionGetDetailed } from '../../../../../_lib/tdStore.js';

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;

  const tdId = String(req.query?.id || '').trim();
  const sectionId = String(req.query?.sectionId || '').trim();
  if (!tdId) return bad(res, 'id is required', 400);
  if (!sectionId) return bad(res, 'sectionId is required', 400);

  return withTiming('td.sections.content', async (timing) => {
    timing.stats.route = '/api/td/:id/sections/:sectionId/content';
    timing.stats.tdId = tdId;

    const item = await timing.db(() => tdSectionGetDetailed(sectionId));
    if (!item || item.tdId !== tdId) {
      timing.setServerTiming(res);
      return bad(res, 'not found', 404);
    }

    timing.addRows(1);
    timing.setServerTiming(res);
    return ok(res, { ok: true, item });
  });
}
