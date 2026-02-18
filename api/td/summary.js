export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad } from '../_lib/http.js';
import { requirePortalAccess } from '../admin/_guard.js';
import { tdSummaryFast } from '../_lib/tdStore.js';
import { getCachedJson, setCachedJson } from '../_lib/tdFastCache.js';
import { withTiming } from '../_lib/timing.js';

const SUMMARY_CACHE_KEY = 'dfs:td:summary:v1';

function setSummaryServerTiming(res, { total, db, kv, cacheHit }) {
  void kv;
  void cacheHit;
  res.setHeader('Server-Timing', `db;dur=${Math.max(0, db)}, total;dur=${Math.max(0, total)}`);
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  const actor = await requirePortalAccess(req, res, { tile: 'td', write: false });
  if (!actor) return;
  if (req.method !== 'GET') return bad(res, 'method not allowed', 405);

  return withTiming('td.summary', async (timing) => {
    timing.stats.route = '/api/td/summary';
    const startedAt = Date.now();

    const cached = await getCachedJson(SUMMARY_CACHE_KEY, timing);
    if (cached && Array.isArray(cached.items)) {
      timing.setCacheHit(true);
      timing.addRows(cached.items.length);
      const total = Date.now() - startedAt;
      setSummaryServerTiming(res, {
        total,
        db: timing.stats.ms_db,
        kv: timing.stats.ms_kv,
        cacheHit: true,
      });
      return ok(res, { ok: true, ...cached, cached: true });
    }

    const summary = await tdSummaryFast();
    const payload = {
      items: summary.items,
      tdCount: summary.tdCount,
      lastUpdatedAt: summary.lastUpdatedAt,
      generatedAt: new Date().toISOString(),
    };
    timing.addRows(payload.items.length);
    await setCachedJson(SUMMARY_CACHE_KEY, payload, timing, 60);

    setSummaryServerTiming(res, {
      total: Date.now() - startedAt,
      db: timing.stats.ms_db,
      kv: timing.stats.ms_kv,
      cacheHit: false,
    });
    return ok(res, { ok: true, ...payload, cached: false });
  });
}
