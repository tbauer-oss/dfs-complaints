export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../../_lib/http.js';
import { requirePortalAccess } from '../../admin/_guard.js';
import { withTiming } from '../../_lib/timing.js';
import { getCachedJson, overviewCacheKey, refreshInBackground, setCachedJson } from '../../_lib/tdFastCache.js';
import { loadOverviewFallback, loadOverviewFromDb } from '../../_lib/tdFastQueries.js';
import { queryWithStatementTimeout } from '../../_lib/db.js';

async function buildOverview(tdId, timing) {
  try {
    const dbOverview = await loadOverviewFromDb(tdId, 4000, (sql, params) => timing.db(() => queryWithStatementTimeout(sql, params, 4000))); 
    if (dbOverview) return dbOverview;
  } catch (err) {
    console.warn('[td/overview] db failed, using fallback', { tdId, message: err?.message || String(err) });
    timing.setColdStartSuspected(true);
  }
  return loadOverviewFallback(tdId);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  const tdId = String(req.query?.id || '').trim();
  if (!tdId) return bad(res, 'id is required', 400);

  return withTiming('td.overview', async (timing) => {
    timing.stats.route = '/api/td/:id/overview';
    timing.stats.tdId = tdId;

    const key = overviewCacheKey(tdId);
    const cached = await getCachedJson(key, timing);
    if (cached) {
      timing.setCacheHit(true);
      timing.setServerTiming(res);
      ok(res, { ok: true, ...cached, cacheHit: true });
      refreshInBackground(async () => {
        const fresh = await buildOverview(tdId, timing);
        if (fresh) await setCachedJson(key, fresh);
      });
      return;
    }

    const overview = await buildOverview(tdId, timing);
    if (!overview) {
      timing.setServerTiming(res);
      return bad(res, 'not found', 404);
    }
    await setCachedJson(key, overview, timing);
    timing.setServerTiming(res);
    return ok(res, { ok: true, ...overview, cacheHit: false });
  });
}
